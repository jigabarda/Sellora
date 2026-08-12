import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/backup/backup_service.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Seeds one account with two businesses and a full sale so the test exercises
/// every foreign key the restore path has to unwind and rebuild.
Future<void> _seed(Database db,
    {required String userId, required String username}) async {
  await db.insert('users', {
    'id': userId,
    'username': username,
    'name': 'Test Owner',
    'salt': 'salt',
    'password_hash': 'hash',
    'created_at': 1,
  });

  for (final b in ['biz_a', 'biz_b']) {
    await db.insert('businesses', {
      'id': '${b}_$userId',
      'user_id': userId,
      'name': b,
      'type': 'retail',
      'address': '',
      'phone': '',
      'created_at': 1,
    });
  }

  final bizId = 'biz_a_$userId';

  await db.insert('categories', {
    'id': catId(userId),
    'business_id': bizId,
    'name': 'Drinks',
    'created_at': 1,
  });
  await db.insert('products', {
    'id': productId(userId),
    'business_id': bizId,
    'category_id': catId(userId),
    'name': 'Coffee',
    'sku': '',
    'price': 50.0,
    'stock': 10,
    'active': 1,
    'created_at': 1,
  });
  await db.insert('customers', {
    'id': customerId(userId),
    'business_id': bizId,
    'name': 'Walk-in Regular',
    'phone': '',
    'email': '',
    'notes': '',
    'created_at': 1,
  });
  await db.insert('sales', {
    'id': saleId(userId),
    'business_id': bizId,
    'customer_id': customerId(userId),
    'total': 100.0,
    'created_at': 1,
  });
  await db.insert('sale_lines', {
    'id': 'lin_$userId',
    'sale_id': saleId(userId),
    'product_id': productId(userId),
    'name': 'Coffee',
    'qty': 2,
    'unit_price': 50.0,
  });
  await db.insert('stock_ledger', {
    'id': 'stk_$userId',
    'business_id': bizId,
    'product_id': productId(userId),
    'delta': -2,
    'reason': 'sale',
    'ref_id': saleId(userId),
    'note': '',
    'at': 1,
  });
  await db.insert('expenses', {
    'id': 'exp_$userId',
    'business_id': bizId,
    'amount': 20.0,
    'category': 'Supplies',
    'note': '',
    'at': 1,
  });
  await db.insert('refunds', {
    'id': 'ref_$userId',
    'business_id': bizId,
    'sale_id': saleId(userId),
    'amount': 50.0,
    'note': '',
    'restock': 1,
    'at': 1,
  });
}

// Ids are namespaced per account so two seeded users can coexist.
String catId(String userId) => 'cat_$userId';
String productId(String userId) => 'prd_$userId';
String customerId(String userId) => 'cus_$userId';
String saleId(String userId) => 'sal_$userId';

Future<int> _count(Database db, String table) async {
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return (r.first['c'] as int?) ?? 0;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late BackupService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    service = BackupService(db);
  });

  tearDown(() async => db.close());

  test('export captures every table for the account', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');

    final summary = await service.inspect(await service.exportToJson('usr_1'));

    expect(summary.userId, 'usr_1');
    expect(summary.username, 'owner');
    expect(summary.businesses, 2);
    expect(summary.products, 1);
    expect(summary.sales, 1);
    expect(summary.customers, 1);
    expect(summary.counts['sale_lines'], 1);
    expect(summary.counts['stock_ledger'], 1);
    expect(summary.counts['expenses'], 1);
    expect(summary.counts['refunds'], 1);
    expect(summary.counts['categories'], 1);
  });

  test('restore into an empty database rebuilds everything', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    final backup = await service.exportToJson('usr_1');

    // Wipe the account the way a fresh install would look.
    await db.delete('sale_lines');
    await db.delete('stock_ledger');
    await db.delete('refunds');
    await db.delete('sales');
    await db.delete('expenses');
    await db.delete('customers');
    await db.delete('products');
    await db.delete('categories');
    await db.delete('businesses');
    await db.delete('users');
    expect(await _count(db, 'sales'), 0);

    final restoredId = await service.restore(backup);

    expect(restoredId, 'usr_1');
    expect(await _count(db, 'users'), 1);
    expect(await _count(db, 'businesses'), 2);
    expect(await _count(db, 'products'), 1);
    expect(await _count(db, 'sale_lines'), 1);
    expect(await _count(db, 'refunds'), 1);

    final sale =
        (await db.query('sales', where: 'id = ?', whereArgs: [saleId('usr_1')]))
            .single;
    expect(sale['total'], 100.0);
    expect(sale['customer_id'], customerId('usr_1'));
  });

  test('restore over existing data replaces it instead of duplicating',
      () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    final backup = await service.exportToJson('usr_1');

    // Activity after the backup was taken; restoring must roll it back.
    await db.insert('sales', {
      'id': 'sal_2',
      'business_id': 'biz_a_usr_1',
      'customer_id': null,
      'total': 999.0,
      'created_at': 2,
    });
    expect(await _count(db, 'sales'), 2);

    await service.restore(backup);

    expect(await _count(db, 'sales'), 1);
    expect(await _count(db, 'businesses'), 2);
    expect(await _count(db, 'products'), 1);
    expect(await _count(db, 'sale_lines'), 1);
  });

  test('restore leaves another local account untouched', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    await _seed(db, userId: 'usr_2', username: 'other');
    final backup = await service.exportToJson('usr_1');

    await service.restore(backup);

    final otherBusinesses = await db.query(
      'businesses',
      where: 'user_id = ?',
      whereArgs: ['usr_2'],
    );
    expect(otherBusinesses.length, 2);
  });

  test('a failed restore leaves current data intact', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    final envelope =
        jsonDecode(await service.exportToJson('usr_1')) as Map<String, Object?>;

    // Point a sale line at a product that is not in the backup. The insert
    // violates the foreign key, so the whole transaction must roll back.
    final tables = envelope['tables']! as Map<String, Object?>;
    (tables['sale_lines']! as List).add({
      'id': 'lin_bad',
      'sale_id': saleId('usr_1'),
      'product_id': 'prd_does_not_exist',
      'name': 'Ghost',
      'qty': 1,
      'unit_price': 1.0,
    });

    await expectLater(
      service.restore(jsonEncode(envelope)),
      throwsA(isA<DatabaseException>()),
    );

    expect(await _count(db, 'businesses'), 2);
    expect(await _count(db, 'sales'), 1);
    expect(await _count(db, 'sale_lines'), 1);
  });

  test('rejects a file that is not a Sellora backup', () async {
    await expectLater(
      service.restore('{"hello":"world"}'),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
        service.restore('not json at all'), throwsA(isA<BackupException>()));
  });

  test('rejects a backup from a newer schema', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    final envelope =
        jsonDecode(await service.exportToJson('usr_1')) as Map<String, Object?>;
    envelope['schemaVersion'] = backupSchemaVersion + 1;

    await expectLater(
      service.restore(jsonEncode(envelope)),
      throwsA(isA<BackupException>()),
    );
  });

  test('refuses when another account already owns the username', () async {
    await _seed(db, userId: 'usr_1', username: 'owner');
    final backup = await service.exportToJson('usr_1');

    await db.delete('businesses', where: 'user_id = ?', whereArgs: ['usr_1']);
    await db.delete('users', where: 'id = ?', whereArgs: ['usr_1']);
    // Same username, different id — the UNIQUE index would blow up mid-restore.
    await _seed(db, userId: 'usr_other', username: 'owner');

    await expectLater(service.restore(backup), throwsA(isA<BackupException>()));
  });
}
