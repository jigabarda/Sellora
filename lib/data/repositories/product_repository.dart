import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';
import '../../util/ids.dart';

/// At or below this, a product counts as low stock.
///
/// One definition, because the Inventory screen and this repository both
/// decide what "low" means and had drifted apart — see [ProductRepository.listLowStock].
const kLowStockThreshold = 5;

class ProductRepository {
  ProductRepository(this._db);

  final Database _db;
  static const _table = 'products';
  static const _ledger = 'stock_ledger';

  Future<List<Product>> listForBusiness(String businessId,
      {String? search}) async {
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      final rows = await _db.query(
        _table,
        where: 'business_id = ? AND (name LIKE ? OR sku LIKE ?)',
        whereArgs: [businessId, q, q],
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return rows.map(Product.fromMap).toList(growable: false);
    }
    final rows = await _db.query(
      _table,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Product.fromMap).toList(growable: false);
  }

  Future<Product?> getById(String id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> countActive(String businessId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE business_id = ? AND active = 1',
      [businessId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Inserts product and optional initial stock ledger row.
  Future<void> insert(Product p, {String initialNote = 'Initial stock'}) async {
    await _db.transaction((txn) async {
      await txn.insert(_table, p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort);
      if (p.stock != 0) {
        await txn.insert(_ledger, {
          'id': newLocalId('stk'),
          'business_id': p.businessId,
          'product_id': p.id,
          'delta': p.stock,
          'reason': 'initial',
          'ref_id': p.id,
          'note': initialNote,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<void> update(Product p) async {
    await _db.update(_table, p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> applyStockDelta({
    required String businessId,
    required String productId,
    required int delta,
    required String reason,
    String? refId,
    String note = '',
  }) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE $_table SET stock = stock + ? WHERE id = ?',
        [delta, productId],
      );
      await txn.insert(_ledger, {
        'id': newLocalId('stk'),
        'business_id': businessId,
        'product_id': productId,
        'delta': delta,
        'reason': reason,
        'ref_id': refId,
        'note': note,
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<List<StockLedgerEntry>> ledgerForBusiness(String businessId,
      {int limit = 200}) async {
    final rows = await _db.query(
      _ledger,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'at DESC',
      limit: limit,
    );
    return rows.map(StockLedgerEntry.fromMap).toList(growable: false);
  }

  /// Untracked products are excluded: they have no inventory to run low on,
  /// and their `stock` column sits at 0 forever. Inactive ones are excluded
  /// too — a delisted product cannot be sold, so it cannot run out.
  Future<List<Product>> listLowStock(String businessId,
      {int threshold = kLowStockThreshold}) async {
    final rows = await _db.query(
      _table,
      where:
          'business_id = ? AND active = 1 AND track_stock = 1 AND stock <= ?',
      whereArgs: [businessId, threshold],
      orderBy: 'stock ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(Product.fromMap).toList(growable: false);
  }
}
