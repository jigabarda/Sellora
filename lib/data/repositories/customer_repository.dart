import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';

class CustomerRepository {
  CustomerRepository(this._db);

  final Database _db;
  static const _table = 'customers';

  Future<List<Customer>> listForBusiness(String businessId,
      {String? search}) async {
    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      final rows = await _db.query(
        _table,
        where: 'business_id = ? AND (name LIKE ? OR phone LIKE ?)',
        whereArgs: [businessId, q, q],
        orderBy: 'name COLLATE NOCASE ASC',
      );
      return rows.map(Customer.fromMap).toList(growable: false);
    }
    final rows = await _db.query(
      _table,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Customer.fromMap).toList(growable: false);
  }

  Future<Customer?> getById(String id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<void> insert(Customer c) async {
    await _db.insert(_table, c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> update(Customer c) async {
    final updated =
        await _db.update(_table, c.toMap(), where: 'id = ?', whereArgs: [c.id]);
    if (updated != 1) {
      throw StateError('That customer no longer exists.');
    }
  }

  /// Past sales survive. `sales.customer_id` is ON DELETE SET NULL, so the
  /// revenue history stays intact and simply loses its customer link.
  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
