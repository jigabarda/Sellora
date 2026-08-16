import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import 'insight.dart';

final _weekdayName = DateFormat('EEEE');

/// How far back the burn-rate calculation looks. Long enough to smooth out a
/// quiet week, short enough that a product's habits three months ago do not
/// drown out what it is doing now.
const _burnWindowDays = 14;

/// A run-out further away than this is not news — the owner will restock long
/// before it matters, and an insight nobody acts on trains them to ignore the
/// whole list.
const _runOutHorizonDays = 7;

/// Distinct days a product must have sold on before its burn rate is treated
/// as a rate at all. Two sales on one afternoon is an event, not a trend.
const _minSaleDaysForBurn = 3;

const _profitWindowDays = 7;

const _weekdayWindowWeeks = 8;

/// Every weekday must have come round this many times before they can be
/// compared. Three Tuesdays is not a pattern.
const _minWeekdayOccurrences = 4;

/// ...and the window overall needs this many sales, or the per-weekday
/// averages are each built from one or two transactions.
const _minSalesForWeekdayPattern = 20;

/// Best-to-worst difference below this is noise dressed up as a finding.
const _weekdayGapThreshold = 0.4;

/// Shorter than the 60 days the design sketch suggested: these businesses turn
/// stock over daily, so six weeks of no movement is already dead. The gate
/// below (the product must be older than this) is what keeps it honest.
const _deadStockDays = 45;

const _minSalesForRefundRate = 5;
const _minRefundsForRate = 2;

/// Purchases needed before a customer has a "rhythm" to have broken.
const _minPurchasesForRhythm = 3;

/// A customer is quiet once they are this many times past their own average
/// gap — and never before [_quietFloorDays], so a daily buyer missing two days
/// is not news.
const _quietMultiplier = 2.0;
const _quietFloorDays = 14;

/// Each rule contributes at most this many insights. The rules point at a
/// screen that lists everything (Inventory, Refunds); the insight is the
/// nudge, not the report. Without a cap, one bad week buries every other rule.
const _maxPerRule = 3;

/// Derives plain-language observations from the business's own records.
///
/// Every rule here is arithmetic — no model, no network, no inference beyond a
/// straight line. That is the point: the owner can check any sentence this
/// produces against numbers they already know, which is exactly what they
/// cannot do with generated text.
///
/// **Every rule carries a minimum-evidence gate and fails closed.** An insight
/// derived from two data points is worse than no insight, because the reader
/// has no way to tell it apart from a well-founded one. When a gate fails the
/// rule returns nothing; it never degrades into a hedge like "you may be
/// running low".
class InsightsService {
  InsightsService(this._db);

  final Database _db;

  /// Runs every rule and returns them worst-first.
  ///
  /// [now] is injectable so tests can pin the clock; production passes null.
  Future<List<Insight>> generate(String businessId, {DateTime? now}) async {
    final reference = now ?? DateTime.now();

    final results = await Future.wait([
      stockRunOut(businessId, now: reference),
      profitDirection(businessId, now: reference),
      weekdayPattern(businessId, now: reference),
      deadStock(businessId, now: reference),
      refundConcentration(businessId, now: reference),
      quietCustomers(businessId, now: reference),
    ]);

    final all = results.expand((r) => r).toList()
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return all;
  }

  // --- 1. Stock run-out ------------------------------------------------------

  /// Products whose current stock will not last the week at the rate they have
  /// actually been selling.
  Future<List<Insight>> stockRunOut(
    String businessId, {
    required DateTime now,
  }) async {
    final windowStart = _localDay(now).subtract(
      const Duration(days: _burnWindowDays),
    );

    // Only tracked, active products — an untracked service has no inventory to
    // exhaust and a delisted product cannot be sold. Same pair of conditions as
    // `ProductRepository.listLowStock`; these two definitions disagreeing is
    // what made the dashboard and Inventory report different low-stock counts.
    final rows = await _db.rawQuery('''
SELECT p.id AS product_id, p.name AS name, p.stock AS stock, p.unit AS unit,
       p.created_at AS created_at, l.delta AS delta, l.at AS at
FROM products p
INNER JOIN stock_ledger l ON l.product_id = p.id
WHERE p.business_id = ?
  AND p.track_stock = 1
  AND p.active = 1
  AND l.reason = 'sale'
  AND l.at >= ?
''', [businessId, windowStart.millisecondsSinceEpoch]);

    final byProduct = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      byProduct.putIfAbsent(row['product_id']! as String, () => []).add(row);
    }

    final insights = <Insight>[];
    for (final entry in byProduct.entries) {
      final first = entry.value.first;
      final stock = (first['stock'] as num).toInt();
      if (stock <= 0) continue; // Already out; the low-stock tile covers it.

      // Sales are negative deltas. A positive one under reason 'sale' would be
      // a restock miscategorised, and counting it would understate the burn.
      var sold = 0;
      final saleDays = <DateTime>{};
      for (final row in entry.value) {
        final delta = (row['delta'] as num).toInt();
        if (delta >= 0) continue;
        sold += -delta;
        saleDays.add(
          _localDay(DateTime.fromMillisecondsSinceEpoch(row['at']! as int)),
        );
      }

      if (saleDays.length < _minSaleDaysForBurn || sold <= 0) continue;

      // Divided by how long the product has existed within the window, not by
      // the window itself and not by the days it happened to sell. A product
      // added four days ago has four days of history, and dividing that by
      // fourteen would report a burn rate a quarter of the truth.
      final created = DateTime.fromMillisecondsSinceEpoch(
        first['created_at']! as int,
      );
      final observedFrom =
          created.isAfter(windowStart) ? _localDay(created) : windowStart;
      final observedDays =
          _daysBetween(observedFrom, now).clamp(1, _burnWindowDays);

      final perDay = sold / observedDays;
      final daysLeft = (stock / perDay).floor();
      if (daysLeft > _runOutHorizonDays) continue;

      final unit = (first['unit'] as String?) ?? '';
      insights.add(Insight(
        id: 'stock_out_${entry.key}',
        severity:
            daysLeft <= 2 ? InsightSeverity.critical : InsightSeverity.warning,
        icon: Icons.trending_down,
        title: '${first['name']} ${_runsOutPhrase(daysLeft)}',
        detail: "You're selling about ${_rate(perDay)} $unit a day "
            'and have $stock left.',
        actionLabel: 'View product',
        actionRoute: '/business/$businessId/products/edit/${entry.key}',
      ));
    }

    insights.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return insights.take(_maxPerRule).toList();
  }

  // --- 2. Profit direction ---------------------------------------------------

  /// Whether the business made or lost money this week, and which expense
  /// categories drove it.
  Future<List<Insight>> profitDirection(
    String businessId, {
    required DateTime now,
  }) async {
    final business = await _db.query(
      'businesses',
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [businessId],
      limit: 1,
    );
    if (business.isEmpty) return const [];

    // A business opened three days ago has no week to report on. Reporting one
    // anyway would compare a partial week against nothing.
    final created = DateTime.fromMillisecondsSinceEpoch(
      business.first['created_at']! as int,
    );
    if (_daysBetween(_localDay(created), now) < _profitWindowDays) {
      return const [];
    }

    final windowStart = _localDay(now).subtract(
      const Duration(days: _profitWindowDays),
    );
    final priorStart = windowStart.subtract(
      const Duration(days: _profitWindowDays),
    );

    final revenue = await _sum(
      'SELECT COALESCE(SUM(total), 0) AS s FROM sales '
      'WHERE business_id = ? AND created_at >= ?',
      [businessId, windowStart.millisecondsSinceEpoch],
    );
    final spend = await _sum(
      'SELECT COALESCE(SUM(amount), 0) AS s FROM expenses '
      'WHERE business_id = ? AND at >= ?',
      [businessId, windowStart.millisecondsSinceEpoch],
    );
    if (revenue == 0 && spend == 0) return const [];

    final profit = revenue - spend;

    final categories = await _db.rawQuery('''
SELECT category, SUM(amount) AS total
FROM expenses
WHERE business_id = ? AND at >= ?
GROUP BY category
ORDER BY total DESC
LIMIT 2
''', [businessId, windowStart.millisecondsSinceEpoch]);

    final drivers = categories
        .map((c) => '${c['category']} (${formatPhp((c['total'] as num))})')
        .join(' and ');

    // The prior window only earns a mention when it actually holds data —
    // "down from ₱0" reads as a collapse when it really means "no records".
    final priorRevenue = await _sum(
      'SELECT COALESCE(SUM(total), 0) AS s FROM sales '
      'WHERE business_id = ? AND created_at >= ? AND created_at < ?',
      [
        businessId,
        priorStart.millisecondsSinceEpoch,
        windowStart.millisecondsSinceEpoch,
      ],
    );
    final comparison = priorRevenue > 0
        ? ' Sales were ${formatPhp(priorRevenue)} the week before.'
        : '';

    final losing = profit < 0;
    return [
      Insight(
        id: 'profit_direction',
        severity: losing ? InsightSeverity.warning : InsightSeverity.info,
        icon: losing ? Icons.trending_down : Icons.trending_up,
        title: losing
            ? "You're ${formatPhp(profit.abs())} down this week"
            : 'You made ${formatPhp(profit)} this week',
        detail: '${formatPhp(spend)} in expenses against '
            '${formatPhp(revenue)} in sales over the last '
            '$_profitWindowDays days.'
            '${drivers.isEmpty ? '' : ' Mostly $drivers.'}'
            '$comparison',
        actionLabel: 'Open reports',
        actionRoute: '/business/$businessId/reports',
      ),
    ];
  }

  // --- 3. Day-of-week pattern ------------------------------------------------

  /// Which day of the week reliably outsells the others.
  Future<List<Insight>> weekdayPattern(
    String businessId, {
    required DateTime now,
  }) async {
    final windowStart = _localDay(now).subtract(
      const Duration(days: _weekdayWindowWeeks * 7),
    );

    final rows = await _db.query(
      'sales',
      columns: ['total', 'created_at'],
      where: 'business_id = ? AND created_at >= ?',
      whereArgs: [businessId, windowStart.millisecondsSinceEpoch],
    );
    if (rows.length < _minSalesForWeekdayPattern) return const [];

    // Every weekday must have come round enough times, which is a property of
    // the window rather than of the sales in it — a weekday with no sales at
    // all is a real observation and has to be allowed to be the worst one.
    final elapsedDays = _daysBetween(windowStart, now);
    if (elapsedDays ~/ 7 < _minWeekdayOccurrences) return const [];

    final totals = <int, double>{for (var d = 1; d <= 7; d++) d: 0};
    final occurrences = <int, int>{for (var d = 1; d <= 7; d++) d: 0};
    for (var i = 0; i < elapsedDays; i++) {
      occurrences.update(
        windowStart.add(Duration(days: i)).weekday,
        (v) => v + 1,
      );
    }
    for (final row in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int);
      totals.update(at.weekday, (v) => v + (row['total'] as num).toDouble());
    }
    if (occurrences.values.any((c) => c < _minWeekdayOccurrences)) {
      return const [];
    }

    final averages = {
      for (final d in totals.keys) d: totals[d]! / occurrences[d]!,
    };
    final best = averages.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final worst = averages.entries.reduce((a, b) => a.value <= b.value ? a : b);
    if (best.value <= 0) return const [];

    // A few percent between best and worst is not a finding, it is variance.
    final gap = (best.value - worst.value) / best.value;
    if (gap < _weekdayGapThreshold) return const [];

    final bestDay = _weekdayName.format(DateTime(2024, 1, best.key));
    final worstDay = _weekdayName.format(DateTime(2024, 1, worst.key));
    return [
      Insight(
        id: 'weekday_pattern',
        severity: InsightSeverity.info,
        icon: Icons.calendar_today_outlined,
        title: '${worstDay}s are your slowest day',
        detail: 'About ${formatPhp(worst.value)} on an average $worstDay '
            'against ${formatPhp(best.value)} on a $bestDay, over the last '
            '$_weekdayWindowWeeks weeks.',
        actionLabel: 'Open reports',
        actionRoute: '/business/$businessId/reports',
      ),
    ];
  }

  // --- 4. Dead stock ---------------------------------------------------------

  /// Stock that has not moved in weeks, and what it is tying up.
  Future<List<Insight>> deadStock(
    String businessId, {
    required DateTime now,
  }) async {
    final cutoff = _localDay(now).subtract(
      const Duration(days: _deadStockDays),
    );

    // The product must predate the cutoff, or something added last week counts
    // as having "stopped" selling. Stock must be positive — a dead product with
    // nothing on the shelf is tying up nothing and needs no action.
    final rows = await _db.rawQuery('''
SELECT p.id AS id, p.name AS name, p.stock AS stock, p.unit AS unit,
       p.price AS price
FROM products p
WHERE p.business_id = ?
  AND p.track_stock = 1
  AND p.active = 1
  AND p.stock > 0
  AND p.created_at < ?
  AND NOT EXISTS (
    SELECT 1 FROM sale_lines sl
    INNER JOIN sales s ON s.id = sl.sale_id
    WHERE sl.product_id = p.id AND s.created_at >= ?
  )
ORDER BY p.price * p.stock DESC
''', [
      businessId,
      cutoff.millisecondsSinceEpoch,
      cutoff.millisecondsSinceEpoch,
    ]);

    return rows.take(_maxPerRule).map((row) {
      final stock = (row['stock'] as num).toInt();
      final value = (row['price'] as num).toDouble() * stock;
      return Insight(
        id: 'dead_stock_${row['id']}',
        severity: InsightSeverity.info,
        icon: Icons.inventory_2_outlined,
        title: "${row['name']} hasn't sold in $_deadStockDays days",
        detail: '$stock ${row['unit']} on the shelf, '
            'worth ${formatPhp(value)}.',
        actionLabel: 'View product',
        actionRoute: '/business/$businessId/products/edit/${row['id']}',
      );
    }).toList();
  }

  // --- 5. Refund concentration -----------------------------------------------

  /// Products refunded far more often than the rest.
  ///
  /// Only single-line sales are counted. A refund records an amount against a
  /// sale, not against an item, so on a three-item sale there is no honest way
  /// to say which product was returned — and guessing would put a quality
  /// complaint against the wrong product's name.
  Future<List<Insight>> refundConcentration(
    String businessId, {
    required DateTime now,
  }) async {
    final rows = await _db.rawQuery('''
SELECT sl.product_id AS product_id,
       sl.name AS name,
       COUNT(*) AS sales,
       SUM(CASE WHEN r.id IS NOT NULL THEN 1 ELSE 0 END) AS refunds
FROM sales s
INNER JOIN sale_lines sl ON sl.sale_id = s.id
LEFT JOIN refunds r ON r.sale_id = s.id
WHERE s.business_id = ?
  AND (SELECT COUNT(*) FROM sale_lines x WHERE x.sale_id = s.id) = 1
GROUP BY sl.product_id
HAVING sales >= ? AND refunds >= ?
ORDER BY (CAST(refunds AS REAL) / sales) DESC
''', [businessId, _minSalesForRefundRate, _minRefundsForRate]);

    return rows.take(_maxPerRule).map((row) {
      final sales = (row['sales'] as num).toInt();
      final refunds = (row['refunds'] as num).toInt();
      return Insight(
        id: 'refund_rate_${row['product_id']}',
        severity: InsightSeverity.warning,
        icon: Icons.replay,
        title: '${row['name']} is refunded often',
        detail: '$refunds of $sales sales were refunded. '
            'Worth checking quality or how it is described.',
        actionLabel: 'Open refunds',
        actionRoute: '/business/$businessId/refunds',
      );
    }).toList();
  }

  // --- 6. Quiet customers ----------------------------------------------------

  /// Regulars who have broken their own buying rhythm.
  Future<List<Insight>> quietCustomers(
    String businessId, {
    required DateTime now,
  }) async {
    final rows = await _db.rawQuery('''
SELECT c.id AS id, c.name AS name, s.created_at AS at
FROM customers c
INNER JOIN sales s ON s.customer_id = c.id
WHERE c.business_id = ?
ORDER BY c.id ASC, s.created_at ASC
''', [businessId]);

    final byCustomer = <String, List<DateTime>>{};
    final names = <String, String>{};
    for (final row in rows) {
      final id = row['id']! as String;
      names[id] = row['name']! as String;
      byCustomer.putIfAbsent(id, () => []).add(
            DateTime.fromMillisecondsSinceEpoch(row['at']! as int),
          );
    }

    final insights = <Insight>[];
    for (final entry in byCustomer.entries) {
      final purchases = entry.value;
      // Needs a rhythm before it can be broken: two purchases give one gap,
      // which is a coincidence rather than a habit.
      if (purchases.length < _minPurchasesForRhythm) continue;

      final span = _daysBetween(
        _localDay(purchases.first),
        _localDay(purchases.last),
      );
      final averageGap = span / (purchases.length - 1);
      if (averageGap <= 0) continue;

      final silentFor = _daysBetween(_localDay(purchases.last), now);
      if (silentFor < _quietFloorDays) continue;
      if (silentFor < averageGap * _quietMultiplier) continue;

      insights.add(Insight(
        id: 'quiet_customer_${entry.key}',
        severity: InsightSeverity.info,
        icon: Icons.person_outline,
        title: '${names[entry.key]} has gone quiet',
        detail: 'Last bought $silentFor days ago, having averaged a visit '
            'every ${_rate(averageGap)} days across '
            '${purchases.length} purchases.',
        actionLabel: 'View customer',
        actionRoute: '/business/$businessId/customers/edit/${entry.key}',
      ));
    }

    insights.sort((a, b) => a.id.compareTo(b.id));
    return insights.take(_maxPerRule).toList();
  }

  // --- helpers ---------------------------------------------------------------

  Future<double> _sum(String sql, List<Object?> args) async {
    final rows = await _db.rawQuery(sql, args);
    return ((rows.first['s'] as num?) ?? 0).toDouble();
  }
}

/// Midnight local. Every window in this file is measured in whole local days,
/// so that a sale at 11pm and one at 1am the next morning land on the days the
/// owner would put them on.
DateTime _localDay(DateTime at) => DateTime(at.year, at.month, at.day);

/// Whole days between two instants, counted on the calendar rather than in
/// elapsed hours — a 23-hour daylight-saving day is still one day.
int _daysBetween(DateTime from, DateTime to) =>
    _localDay(to).difference(_localDay(from)).inDays;

String _rate(double value) =>
    value >= 10 ? value.round().toString() : value.toStringAsFixed(1);

String _runsOutPhrase(int days) => switch (days) {
      <= 0 => 'runs out today',
      1 => 'runs out tomorrow',
      _ => 'runs out in about $days days',
    };
