import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/repositories/business_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Seeds a business carrying one of every child row, including a recorded sale.
/// The sale is what makes deletion interesting: `sale_lines.product_id` is
/// ON DELETE RESTRICT.
Future<void> _seedBusiness(
  Database db, {
  required String userId,
  required String bizId,
}) async {
  await db.insert(
      'users',
      {
        'id': userId,
        'email': '$userId@test.com',
        'name': 'Owner',
        'salt': 'salt',
        'password_hash': 'hash',
        'created_at': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.insert('businesses', {
    'id': bizId,
    'user_id': userId,
    'name': 'Store $bizId',
    'type': 'Retail Store',
    'address': '',
    'phone': '',
    'created_at': 1,
  });
  await db.insert('categories', {
    'id': 'cat_$bizId',
    'business_id': bizId,
    'name': 'Drinks',
    'created_at': 1,
  });
  await db.insert('products', {
    'id': 'prd_$bizId',
    'business_id': bizId,
    'category_id': 'cat_$bizId',
    'name': 'Coffee',
    'sku': '',
    'price': 50.0,
    'stock': 8,
    'active': 1,
    'created_at': 1,
  });
  await db.insert('customers', {
    'id': 'cus_$bizId',
    'business_id': bizId,
    'name': 'Regular',
    'phone': '',
    'email': '',
    'notes': '',
    'created_at': 1,
  });
  await db.insert('sales', {
    'id': 'sal_$bizId',
    'business_id': bizId,
    'customer_id': 'cus_$bizId',
    'total': 100.0,
    'created_at': 1,
  });
  await db.insert('sale_lines', {
    'id': 'lin_$bizId',
    'sale_id': 'sal_$bizId',
    'product_id': 'prd_$bizId',
    'name': 'Coffee',
    'qty': 2,
    'unit_price': 50.0,
  });
  await db.insert('stock_ledger', {
    'id': 'stk_$bizId',
    'business_id': bizId,
    'product_id': 'prd_$bizId',
    'delta': -2,
    'reason': 'sale',
    'ref_id': 'sal_$bizId',
    'note': '',
    'at': 1,
  });
  await db.insert('expenses', {
    'id': 'exp_$bizId',
    'business_id': bizId,
    'amount': 20.0,
    'category': 'Supplies',
    'note': '',
    'at': 1,
  });
  await db.insert('refunds', {
    'id': 'ref_$bizId',
    'business_id': bizId,
    'sale_id': 'sal_$bizId',
    'amount': 50.0,
    'note': '',
    'restock': 1,
    'at': 1,
  });
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return (rows.first['c'] as int?) ?? 0;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late BusinessRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    repo = BusinessRepository(db);
  });

  tearDown(() async => db.close());

  test('products cannot be dropped while sale lines still reference them',
      () async {
    await _seedBusiness(db, userId: 'usr_1', bizId: 'biz_1');

    // The hazard `delete`'s ordering exists to avoid: RESTRICT on
    // sale_lines.product_id means products must go after sale_lines, even
    // though both hang off the same business.
    await expectLater(
      db.delete('products', where: 'business_id = ?', whereArgs: ['biz_1']),
      throwsA(isA<DatabaseException>()),
    );
    expect(await _count(db, 'products'), 1);
  });

  test('delete removes the business and every child row', () async {
    await _seedBusiness(db, userId: 'usr_1', bizId: 'biz_1');

    await repo.delete('biz_1');

    for (final table in [
      'businesses',
      'categories',
      'products',
      'customers',
      'sales',
      'sale_lines',
      'stock_ledger',
      'expenses',
      'refunds',
    ]) {
      expect(await _count(db, table), 0, reason: '$table should be empty');
    }
    // The account itself survives; only the business was deleted.
    expect(await _count(db, 'users'), 1);
  });

  test('delete leaves a sibling business untouched', () async {
    await _seedBusiness(db, userId: 'usr_1', bizId: 'biz_1');
    await _seedBusiness(db, userId: 'usr_1', bizId: 'biz_2');

    await repo.delete('biz_1');

    expect(await _count(db, 'businesses'), 1);
    expect(await _count(db, 'sale_lines'), 1);
    final remaining = await db.query('sale_lines');
    expect(remaining.single['id'], 'lin_biz_2');
    expect(await _count(db, 'products'), 1);
    expect(await _count(db, 'refunds'), 1);
  });

  test('updateProfile writes the editable fields and keeps ownership',
      () async {
    await _seedBusiness(db, userId: 'usr_1', bizId: 'biz_1');

    await repo.updateProfile(
      id: 'biz_1',
      name: 'Renamed Store',
      type: 'Water Station',
      address: '12 Mabini St',
      phone: '0917-000-0000',
    );

    final business = (await repo.getById('biz_1'))!;
    expect(business.name, 'Renamed Store');
    expect(business.type, 'Water Station');
    expect(business.address, '12 Mabini St');
    expect(business.phone, '0917-000-0000');
    expect(business.userId, 'usr_1');
    expect(business.createdAt.millisecondsSinceEpoch, 1);
  });

  test('updateProfile on a deleted business throws instead of silently passing',
      () async {
    await expectLater(
      repo.updateProfile(
        id: 'biz_gone',
        name: 'Ghost',
        type: 'Other',
        address: '',
        phone: '',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
