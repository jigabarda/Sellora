import 'package:sqflite/sqflite.dart';

import '../models/entities.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final Database _db;

  static const _table = 'categories';

  Future<List<Category>> listForBusiness(String businessId) async {
    final rows = await _db.query(
      _table,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Category.fromMap).toList(growable: false);
  }

  /// How many products sit in each category, keyed by category id.
  ///
  /// Uncategorized products are not counted — they have a null `category_id`
  /// and so belong to no key here.
  Future<Map<String, int>> productCounts(String businessId) async {
    final rows = await _db.rawQuery(
      'SELECT category_id, COUNT(*) AS c FROM products '
      'WHERE business_id = ? AND category_id IS NOT NULL '
      'GROUP BY category_id',
      [businessId],
    );
    return {
      for (final row in rows)
        row['category_id']! as String: (row['c'] as int?) ?? 0,
    };
  }

  Future<void> insert(Category category) async {
    await _db.insert(_table, category.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> rename({required String id, required String name}) async {
    final updated = await _db.update(
      _table,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated != 1) {
      throw StateError('That category no longer exists.');
    }
  }

  /// Names are unique per business, case-insensitively. SQLite has no partial
  /// unique index here, so the check lives in code; [exceptId] lets a rename
  /// keep its own name.
  Future<bool> nameExists({
    required String businessId,
    required String name,
    String? exceptId,
  }) async {
    final rows = await _db.query(
      _table,
      where: 'business_id = ? AND name = ? COLLATE NOCASE'
          '${exceptId == null ? '' : ' AND id != ?'}',
      whereArgs: [businessId, name.trim(), if (exceptId != null) exceptId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Products in this category are not deleted. `products.category_id` is
  /// ON DELETE SET NULL, so they fall back to uncategorized.
  Future<void> delete(String id) async {
    await _db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}
