import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';
import '../../util/ids.dart';

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
      final at =
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int);
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
       SUM(sl.qty * sl.unit_price) AS rev
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
    required List<({String productId, String name, int qty, double unitPrice})>
        lines,
    String? customerId,
  }) async {
    final saleId = newLocalId('sale');
    final now = DateTime.now().millisecondsSinceEpoch;
    double total = 0;
    for (final l in lines) {
      total += l.qty * l.unitPrice;
    }

    // Products that do not track stock — services, made-to-order items — have
    // no inventory to check or decrement. Resolved once here so the write loop
    // below does not query for it a second time.
    final tracked = <String, bool>{};

    await _db.transaction((txn) async {
      for (final l in lines) {
        final rows = await txn.query(
          _products,
          columns: ['stock', 'track_stock'],
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
          'reason': 'sale',
          'ref_id': saleId,
          'note': '',
          'at': now,
        });
      }
    });

    return saleId;
  }

  /// Revenue grouped by product name for a period (from sale_lines joined sales).
  Future<Map<String, double>> topProductsByRevenue(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.rawQuery(
      '''
SELECT sl.name AS name, SUM(sl.qty * sl.unit_price) AS rev
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
