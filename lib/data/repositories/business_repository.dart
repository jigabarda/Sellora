import 'package:sqflite/sqflite.dart';

class Business {
  const Business({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.address,
    required this.phone,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final String type;
  final String address;
  final String phone;
  final DateTime createdAt;

  factory Business.fromMap(Map<String, Object?> map) {
    return Business(
      id: map['id']! as String,
      userId: (map['user_id'] as String?) ?? '',
      name: map['name']! as String,
      type: map['type']! as String,
      address: (map['address'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type,
      'address': address,
      'phone': phone,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

class BusinessRepository {
  BusinessRepository(this._db);

  final Database _db;

  static const _table = 'businesses';

  Future<List<Business>> listForUser(String userId) async {
    final rows = await _db.query(
      _table,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Business.fromMap).toList(growable: false);
  }

  Future<Business?> getById(String id) async {
    final rows =
        await _db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Business.fromMap(rows.first);
  }

  Future<void> insert(Business business) async {
    await _db.insert(
      _table,
      business.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Updates the editable profile fields. Ownership and `created_at` are fixed.
  Future<void> updateProfile({
    required String id,
    required String name,
    required String type,
    required String address,
    required String phone,
  }) async {
    final updated = await _db.update(
      _table,
      {'name': name, 'type': type, 'address': address, 'phone': phone},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated != 1) {
      throw StateError('That business no longer exists.');
    }
  }

  /// Deletes a business and every row that belongs to it.
  ///
  /// Children are removed explicitly rather than left to ON DELETE CASCADE.
  /// `sale_lines.product_id` is ON DELETE RESTRICT, so a cascade from
  /// `businesses` only survives if SQLite happens to clear `sales` (and with
  /// it `sale_lines`) before it reaches `products`. It does today, but that
  /// ordering is an implementation detail, not a guarantee — and one more
  /// RESTRICT added to the schema could quietly invert it. Deleting deepest
  /// first inside one transaction does not depend on it.
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM sale_lines WHERE sale_id IN '
        '(SELECT id FROM sales WHERE business_id = ?)',
        [id],
      );
      for (final table in _childTables) {
        await txn.delete(table, where: 'business_id = ?', whereArgs: [id]);
      }
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Child-before-parent. `products` must come after `stock_ledger` and
  /// `sale_lines`, both of which point at it.
  static const _childTables = <String>[
    'stock_ledger',
    'refunds',
    'sales',
    'expenses',
    'customers',
    'products',
    'categories',
  ];
}
