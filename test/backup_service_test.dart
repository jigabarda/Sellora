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

  test('a backup saved as UTF-8 bytes restores its text intact', () async {
    // Saving to Downloads encodes the JSON to bytes by hand, where the share
    // path let dart:io do it. Anything but UTF-8 — or a stray BOM — turns a
    // shop called "Aling Rosa's Tubig — Sampaloc" into mojibake on the new
    // phone, or fails the JSON parse outright.
    await _seed(db, userId: 'usr_1', username: 'owner');
    await db.insert('businesses', {
      'id': 'biz_utf8',
      'user_id': 'usr_1',
      'name': 'Aling Rosa’s Tubig — Sampaloñ',
      'type': 'Water Station',
      'address': '',
      'phone': '',
      'created_at': 1,
    });

    final json = await service.exportToJson('usr_1');
    final bytes = utf8.encode(json);
    // Exactly what comes back off the device: bytes in, string out.
    await service.restore(utf8.decode(bytes));

    final restored =
        (await db.query('businesses', where: 'id = ?', whereArgs: ['biz_utf8']))
            .single;
    expect(restored['name'], 'Aling Rosa’s Tubig — Sampaloñ');
  });

  test('the backup file is named as JSON, since that is what is saved', () {
    final name = backupFileName(DateTime(2026, 8, 19, 10, 31));
    expect(name, 'sellora-backup-2026-08-19-1031.json');
  });

  test('a rental and its discount survive the round trip', () async {
    // The export reads whole rows and the restore writes them back whole, so
    // this is really asking whether anything in between drops a column it has
    // never heard of. A backup that silently loses the days turns a P600
    // booking into P200 on the new phone.
    await _seed(db, userId: 'usr_1', username: 'owner');
    final bizId = 'biz_a_usr_1';

    await db.insert('products', {
      'id': 'prd_chair',
      'business_id': bizId,
      'category_id': null,
      'name': 'Chair',
      'sku': '',
      'price': 10.0,
      'stock': 50,
      'rental': 1,
      'active': 1,
      'created_at': 1,
    });
    await db.insert('sales', {
      'id': 'sale_rent',
      'business_id': bizId,
      'customer_id': null,
      'total': 500.0,
      'discount': 100.0,
      'created_at': 2,
    });
    await db.insert('sale_lines', {
      'id': 'lin_rent',
      'sale_id': 'sale_rent',
      'product_id': 'prd_chair',
      'name': 'Chair',
      'qty': 20,
      'unit_price': 10.0,
      'days': 3,
      'returned_qty': 5,
      'starts_at': DateTime(2026, 8, 19).millisecondsSinceEpoch,
    });

    final backup = await service.exportToJson('usr_1');
    await service.restore(backup);

    final product =
        (await db.query('products', where: 'id = ?', whereArgs: ['prd_chair']))
            .single;
    expect(product['rental'], 1, reason: 'still a rental, not a sale');

    final sale =
        (await db.query('sales', where: 'id = ?', whereArgs: ['sale_rent']))
            .single;
    expect(sale['total'], 500.0);
    expect(sale['discount'], 100.0);

    final line =
        (await db.query('sale_lines', where: 'id = ?', whereArgs: ['lin_rent']))
            .single;
    expect(line['days'], 3, reason: 'P600 of chairs, not P200');
    expect(line['returned_qty'], 5, reason: 'fifteen are still out');
    expect(line['starts_at'], DateTime(2026, 8, 19).millisecondsSinceEpoch);
  });

  test('the file stamps the schema version the app actually uses', () async {
    // The guard that refuses a too-new backup compares against this number,
    // so understating it lets an older build accept a file full of columns it
    // does not have — surfacing as a raw SQLite error mid-restore instead of
    // "update the app first". It was hand-kept at 4 while the database had
    // moved to 8.
    await _seed(db, userId: 'usr_1', username: 'owner');
    final envelope =
        jsonDecode(await service.exportToJson('usr_1')) as Map<String, Object?>;

    expect(envelope['schemaVersion'], SelloraDatabase.schemaVersion);
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
