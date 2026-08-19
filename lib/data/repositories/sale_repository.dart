import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';
import '../../util/ids.dart';

/// One line of a sale that has not been recorded yet.
///
/// A class rather than a record because the optional half keeps growing —
/// days, then a start date — and a record has no defaults, so every new field
/// forced every existing caller to spell out a value it did not care about.
class SaleLineDraft {
  const SaleLineDraft({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    this.days = 1,
    this.startsAt,
  });

  final String productId;
  final String name;
  final int qty;
  final double unitPrice;

  /// One for anything sold outright, so the money is always
  /// `qty * unitPrice * days` and nothing has to branch.
  final int days;

  /// When the rental period starts. Null means "when this is recorded", and
  /// is always null for something sold outright.
  final DateTime? startsAt;
}

class SaleRepository {
  SaleRepository(this._db);

  final Database _db;
  static const _sales = 'sales';
  static const _lines = 'sale_lines';
  static const _products = 'products';
  static const _ledger = 'stock_ledger';

  Future<int> countForBusiness(String businessId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_sales WHERE business_id = ?',
      [businessId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<int> countBetween(
      String businessId, DateTime from, DateTime toExclusive) async {
    final r = await _db.rawQuery(
      '''
SELECT COUNT(*) AS c FROM $_sales
WHERE business_id = ? AND created_at >= ? AND created_at < ?
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch
      ],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<double> sumBetween(
      String businessId, DateTime from, DateTime toExclusive) async {
    final r = await _db.rawQuery(
      '''
SELECT COALESCE(SUM(total), 0) AS s FROM $_sales
WHERE business_id = ? AND created_at >= ? AND created_at < ?
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch
      ],
    );
    return ((r.first['s'] as num?) ?? 0).toDouble();
  }

  Future<List<Sale>> listRecent(String businessId, {int limit = 50}) async {
    final rows = await _db.query(
      _sales,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final sales = <Sale>[];
    for (final row in rows) {
      final id = row['id']! as String;
      final lineRows =
          await _db.query(_lines, where: 'sale_id = ?', whereArgs: [id]);
      final lines = lineRows.map(SaleLine.fromMap).toList(growable: false);
      sales.add(Sale.fromMap(row, lines: lines));
    }
    return sales;
  }

  /// Every sale in the range, oldest first, with its lines.
  ///
  /// Unbounded on purpose: this backs the spreadsheet export, where a missing
  /// row is a wrong total in someone's books. [listRecent]'s limit is right for
  /// a screen and wrong here.
  Future<List<Sale>> listBetween(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.query(
      _sales,
      where: 'business_id = ? AND created_at >= ? AND created_at < ?',
      whereArgs: [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch,
      ],
      orderBy: 'created_at ASC',
    );

    // One query for every line in the range rather than one per sale: a year
    // of sales is thousands of round trips otherwise, and this runs on phones.
    final lineRows = await _db.rawQuery(
      '''
SELECT sl.* FROM $_lines sl
INNER JOIN $_sales s ON s.id = sl.sale_id
WHERE s.business_id = ? AND s.created_at >= ? AND s.created_at < ?
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch,
      ],
    );
    final bySale = <String, List<SaleLine>>{};
    for (final row in lineRows) {
      final line = SaleLine.fromMap(row);
      (bySale[line.saleId] ??= <SaleLine>[]).add(line);
    }

    return rows
        .map((r) => Sale.fromMap(r, lines: bySale[r['id']] ?? const []))
        .toList(growable: false);
  }

  /// Revenue per calendar day, for the trend on the reports screen.
  ///
  /// Bucketed in Dart rather than SQL because the boundary that matters is the
  /// owner's local midnight, and `created_at` is epoch milliseconds. Letting
  /// SQLite group it would silently bucket by UTC and slide every day by the
  /// timezone offset.
  Future<Map<DateTime, double>> revenueByDay(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.query(
      _sales,
      columns: ['total', 'created_at'],
      where: 'business_id = ? AND created_at >= ? AND created_at < ?',
      whereArgs: [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch,
      ],
    );

    final out = <DateTime, double>{};
    for (final row in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int);
      final day = DateTime(at.year, at.month, at.day);
      out[day] = (out[day] ?? 0) + ((row['total'] as num?) ?? 0).toDouble();
    }
    return out;
  }

  /// Units sold and revenue per product name, best first.
  ///
  /// [topProductsByRevenue] answers the same question for a screen and caps at
  /// twenty; the export wants every product and the quantity beside the money.
  Future<List<({String name, int qty, double revenue})>> productPerformance(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.rawQuery(
      '''
SELECT sl.name AS name,
       SUM(sl.qty) AS qty,
       SUM(sl.qty * sl.unit_price * sl.days) AS rev
FROM $_lines sl
INNER JOIN $_sales s ON s.id = sl.sale_id
WHERE s.business_id = ?
  AND s.created_at >= ? AND s.created_at < ?
GROUP BY sl.name
ORDER BY rev DESC
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch,
      ],
    );
    return rows
        .map((r) => (
              name: r['name']! as String,
              qty: ((r['qty'] as num?) ?? 0).toInt(),
              revenue: ((r['rev'] as num?) ?? 0).toDouble(),
            ))
        .toList(growable: false);
  }

  Future<Sale?> getById(String saleId) async {
    final rows =
        await _db.query(_sales, where: 'id = ?', whereArgs: [saleId], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final lineRows =
        await _db.query(_lines, where: 'sale_id = ?', whereArgs: [saleId]);
    final lines = lineRows.map(SaleLine.fromMap).toList(growable: false);
    return Sale.fromMap(row, lines: lines);
  }

  /// Records sale, line items, decrements stock, writes ledger rows.
  Future<String> recordSale({
    required String businessId,
    required List<SaleLineDraft> lines,
    String? customerId,
    double discount = 0,
  }) async {
    final saleId = newLocalId('sale');
    final now = DateTime.now().millisecondsSinceEpoch;
    double subtotal = 0;
    for (final l in lines) {
      // Days is 1 for anything sold outright, so this is the same arithmetic
      // for a sale and a rental.
      subtotal += l.qty * l.unitPrice * l.days;
    }

    // Clamped rather than rejected. A discount larger than the sale is a
    // typo, not a request to hand money over, and refusing the whole sale at
    // the counter over it helps nobody — the most it can do is bring the
    // total to zero.
    final off = discount.isFinite && discount > 0
        ? (discount > subtotal ? subtotal : discount)
        : 0.0;
    final total = subtotal - off;

    // Products that do not track stock — services, made-to-order items — have
    // no inventory to check or decrement. Resolved once here so the write loop
    // below does not query for it a second time.
    final tracked = <String, bool>{};
    // Whether each product is rented rather than sold, so the ledger can name
    // the movement correctly. Read here with the stock check rather than in
    // the write loop, for the same reason `tracked` is.
    final rented = <String, bool>{};

    await _db.transaction((txn) async {
      for (final l in lines) {
        final rows = await txn.query(
          _products,
          columns: ['stock', 'track_stock', 'rental'],
          where: 'id = ? AND business_id = ?',
          whereArgs: [l.productId, businessId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Unknown product ${l.productId}');
        }
        final tracksStock =
            ((rows.first['track_stock'] as num?) ?? 1).toInt() == 1;
        tracked[l.productId] = tracksStock;
        rented[l.productId] =
            ((rows.first['rental'] as num?) ?? 0).toInt() == 1;
        if (!tracksStock) continue;

        final stock = (rows.first['stock'] as num).toInt();
        if (stock < l.qty) {
          throw StateError(
              'Insufficient stock for ${l.name} (have $stock, need ${l.qty})');
        }
      }

      await txn.insert(_sales, {
        'id': saleId,
        'business_id': businessId,
        'customer_id': customerId,
        'total': total,
        'discount': off,
        'created_at': now,
      });

      for (final l in lines) {
        final lineId = newLocalId('ln');
        await txn.insert(_lines, {
          'id': lineId,
          'sale_id': saleId,
          'product_id': l.productId,
          'name': l.name,
          'qty': l.qty,
          'unit_price': l.unitPrice,
          'days': l.days < 1 ? 1 : l.days,
          'returned_qty': 0,
          // Only rentals carry a period. Stamping a start on a sold line
          // would put it in front of the return screen's query.
          'starts_at': rented[l.productId] == true
              ? (l.startsAt ?? DateTime.fromMillisecondsSinceEpoch(now))
                  .millisecondsSinceEpoch
              : null,
        });

        if (tracked[l.productId] != true) continue;

        final updated = await txn.rawUpdate(
          'UPDATE $_products SET stock = stock - ? WHERE id = ? AND business_id = ?',
          [l.qty, l.productId, businessId],
        );
        if (updated != 1) {
          throw StateError('Stock update failed for product ${l.productId}');
        }

        await txn.insert(_ledger, {
          'id': newLocalId('stk'),
          'business_id': businessId,
          'product_id': l.productId,
          'delta': -l.qty,
          // Rented stock leaves the shelf exactly as sold stock does; the
          // difference is that it is expected back. The reason is what lets
          // the ledger tell the two movements apart afterwards, and what
          // `recordRentalReturn` pairs its restock against.
          'reason': rented[l.productId] == true ? 'rental_out' : 'sale',
          'ref_id': saleId,
          'note': '',
          'at': now,
        });
      }
    });

    return saleId;
  }

  /// Everything rented out and not yet back, oldest first.
  ///
  /// Driven off `sale_lines.returned_qty < qty` rather than off a status
  /// column, so a line cannot be marked returned while its quantities say
  /// otherwise — there is one fact here, not two that can disagree.
  Future<List<OutstandingRental>> listOutstandingRentals(
    String businessId,
  ) async {
    final rows = await _db.rawQuery(
      """
SELECT sl.id AS line_id, sl.sale_id, sl.product_id, sl.name, sl.qty,
       sl.returned_qty, sl.days, sl.unit_price, sl.starts_at,
       s.created_at, c.name AS customer_name
FROM $_lines sl
INNER JOIN $_sales s ON s.id = sl.sale_id
INNER JOIN $_products p ON p.id = sl.product_id
LEFT JOIN customers c ON c.id = s.customer_id
WHERE s.business_id = ? AND p.rental = 1 AND sl.returned_qty < sl.qty
ORDER BY COALESCE(sl.starts_at, s.created_at) ASC
""",
      [businessId],
    );

    return rows
        .map((r) => OutstandingRental(
              lineId: r['line_id']! as String,
              saleId: r['sale_id']! as String,
              productId: r['product_id']! as String,
              productName: r['name']! as String,
              qty: (r['qty'] as num).toInt(),
              returnedQty: ((r['returned_qty'] as num?) ?? 0).toInt(),
              days: ((r['days'] as num?) ?? 1).toInt(),
              unitPrice: (r['unit_price'] as num).toDouble(),
              customerName: r['customer_name'] as String?,
              // The stated start when there is one; otherwise when the sale
              // was rung up, which is what a line without dates meant.
              rentedAt: DateTime.fromMillisecondsSinceEpoch(
                ((r['starts_at'] as num?) ?? (r['created_at'] as num)).toInt(),
              ),
            ))
        .toList(growable: false);
  }

  /// Takes [qty] of a rented line back onto the shelf.
  ///
  /// The money is not touched. Revenue was earned when the thing went out and
  /// the customer paid for the period; bringing the chairs back does not undo
  /// that. What comes back is the *stock* — which is the whole reason rentals
  /// cannot simply be sales, since a sale's decrement is permanent and this
  /// one is not.
  ///
  /// Partial returns are allowed on purpose: nineteen of twenty chairs is an
  /// ordinary Sunday, and refusing it would make the owner either lie or wait.
  Future<void> recordRentalReturn({
    required String businessId,
    required String lineId,
    required int qty,
  }) async {
    if (qty < 1) throw StateError('Return at least one.');

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      final rows = await txn.rawQuery(
        """
SELECT sl.qty, sl.returned_qty, sl.product_id, sl.name, sl.sale_id,
       p.track_stock, p.rental
FROM $_lines sl
INNER JOIN $_products p ON p.id = sl.product_id
INNER JOIN $_sales s ON s.id = sl.sale_id
WHERE sl.id = ? AND s.business_id = ?
LIMIT 1
""",
        [lineId, businessId],
      );
      if (rows.isEmpty) throw StateError('That rental is no longer here.');

      final row = rows.first;
      if (((row['rental'] as num?) ?? 0).toInt() != 1) {
        throw StateError('${row['name']} was sold, not rented.');
      }

      final total = (row['qty'] as num).toInt();
      final already = ((row['returned_qty'] as num?) ?? 0).toInt();
      final outstanding = total - already;
      if (qty > outstanding) {
        throw StateError(
          outstanding == 0
              ? 'All of that is already back.'
              : 'Only $outstanding still out.',
        );
      }

      await txn.rawUpdate(
        'UPDATE $_lines SET returned_qty = returned_qty + ? WHERE id = ?',
        [qty, lineId],
      );

      // Untracked rentals have no shelf to come back to, but the return is
      // still recorded above so the line stops showing as outstanding.
      if (((row['track_stock'] as num?) ?? 1).toInt() != 1) return;

      final productId = row['product_id']! as String;
      final updated = await txn.rawUpdate(
        'UPDATE $_products SET stock = stock + ? WHERE id = ? AND business_id = ?',
        [qty, productId, businessId],
      );
      if (updated != 1) {
        throw StateError('Could not put ${row['name']} back on the shelf.');
      }

      await txn.insert(_ledger, {
        'id': newLocalId('stk'),
        'business_id': businessId,
        'product_id': productId,
        'delta': qty,
        'reason': 'rental_return',
        'ref_id': row['sale_id'],
        'note': '',
        'at': now,
      });
    });
  }

  /// Revenue grouped by product name for a period (from sale_lines joined sales).
  Future<Map<String, double>> topProductsByRevenue(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.rawQuery(
      '''
-- `* days` because a rental line is priced per day: leaving it
-- out reported a three-day hire at one day's takings.
SELECT sl.name AS name, SUM(sl.qty * sl.unit_price * sl.days) AS rev
FROM $_lines sl
INNER JOIN $_sales s ON s.id = sl.sale_id
WHERE s.business_id = ?
  AND s.created_at >= ? AND s.created_at < ?
GROUP BY sl.name
ORDER BY rev DESC
LIMIT 20
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch
      ],
    );
    final map = <String, double>{};
    for (final r in rows) {
      map[r['name']! as String] = (r['rev'] as num).toDouble();
    }
    return map;
  }
}
