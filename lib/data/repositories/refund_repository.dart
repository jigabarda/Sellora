import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';
import '../../util/ids.dart';

class RefundRepository {
  RefundRepository(this._db);

  final Database _db;
  static const _table = 'refunds';
  static const _lines = 'sale_lines';
  static const _products = 'products';
  static const _ledger = 'stock_ledger';

  Future<List<Refund>> listForBusiness(String businessId,
      {int limit = 100}) async {
    final rows = await _db.query(
      _table,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'at DESC',
      limit: limit,
    );
    return rows.map(Refund.fromMap).toList(growable: false);
  }

  Future<void> insert(Refund r) async {
    await _db.insert(_table, r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Inserts refund and optionally restores stock from linked sale lines.
  Future<void> processRefund({
    required Refund refund,
    required List<SaleLine>? saleLinesIfRestock,
  }) async {
    await _db.transaction((txn) async {
      await txn.insert(_table, refund.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort);
      if (!refund.restock ||
          refund.saleId == null ||
          saleLinesIfRestock == null) {
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final line in saleLinesIfRestock) {
        await txn.rawUpdate(
          'UPDATE $_products SET stock = stock + ? WHERE id = ? AND business_id = ?',
          [line.qty, line.productId, refund.businessId],
        );
        await txn.insert(_ledger, {
          'id': newLocalId('stk'),
          'business_id': refund.businessId,
          'product_id': line.productId,
          'delta': line.qty,
          'reason': 'refund',
          'ref_id': refund.id,
          'note': 'Restock from refund',
          'at': now,
        });
      }
    });
  }

  Future<List<SaleLine>> linesForSale(String saleId) async {
    final rows =
        await _db.query(_lines, where: 'sale_id = ?', whereArgs: [saleId]);
    return rows.map(SaleLine.fromMap).toList(growable: false);
  }
}
