import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';

class ExpenseRepository {
  ExpenseRepository(this._db);

  final Database _db;
  static const _table = 'expenses';

  Future<List<Expense>> listForBusiness(String businessId,
      {int limit = 200}) async {
    final rows = await _db.query(
      _table,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'at DESC',
      limit: limit,
    );
    return rows.map(Expense.fromMap).toList(growable: false);
  }

  /// Every expense in the range, oldest first. Unbounded, for the same reason
  /// [SaleRepository.listBetween] is: this backs an export, not a screen.
  Future<List<Expense>> listBetween(
    String businessId,
    DateTime from,
    DateTime toExclusive,
  ) async {
    final rows = await _db.query(
      _table,
      where: 'business_id = ? AND at >= ? AND at < ?',
      whereArgs: [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch,
      ],
      orderBy: 'at ASC',
    );
    return rows.map(Expense.fromMap).toList(growable: false);
  }

  Future<double> sumBetween(
      String businessId, DateTime from, DateTime toExclusive) async {
    final r = await _db.rawQuery(
      '''
SELECT COALESCE(SUM(amount), 0) AS s FROM $_table
WHERE business_id = ? AND at >= ? AND at < ?
''',
      [
        businessId,
        from.millisecondsSinceEpoch,
        toExclusive.millisecondsSinceEpoch
      ],
    );
    return ((r.first['s'] as num?) ?? 0).toDouble();
  }

  Future<Expense?> getById(String id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Expense.fromMap(rows.first);
  }

  Future<void> insert(Expense e) async {
    await _db.insert(_table, e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> update(Expense e) async {
    final updated =
        await _db.update(_table, e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    if (updated != 1) {
      throw StateError('That expense no longer exists.');
    }
  }

  /// Nothing references an expense, so this is a plain delete.
  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
