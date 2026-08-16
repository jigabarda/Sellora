import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/models/entities.dart';
import 'package:sellora_mobile/data/repositories/category_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _bizId = 'biz_1';

Future<void> _seedBusiness(Database db) async {
  await db.insert('users', {
    'id': 'usr_1',
    'username': 'owner',
    'name': 'Owner',
    'salt': 'salt',
    'password_hash': 'hash',
    'created_at': 1,
  });
  await db.insert('businesses', {
    'id': _bizId,
    'user_id': 'usr_1',
    'name': 'Store',
    'type': 'Retail Store',
    'address': '',
    'phone': '',
    'created_at': 1,
  });
}

Future<void> _addProduct(
  Database db, {
  required String id,
  String? categoryId,
  String businessId = _bizId,
}) async {
  await db.insert('products', {
    'id': id,
    'business_id': businessId,
    'category_id': categoryId,
    'name': 'Product $id',
    'sku': '',
    'price': 10.0,
    'stock': 1,
    'active': 1,
    'created_at': 1,
  });
}

Category _category(String id, String name, {String businessId = _bizId}) =>
    Category(
      id: id,
      businessId: businessId,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late CategoryRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    repo = CategoryRepository(db);
    await _seedBusiness(db);
  });

  tearDown(() async => db.close());

  test('lists a business\' categories alphabetically, ignoring case', () async {
    await repo.insert(_category('cat_1', 'snacks'));
    await repo.insert(_category('cat_2', 'Drinks'));
    await repo.insert(_category('cat_3', 'apparel'));

    final names =
        (await repo.listForBusiness(_bizId)).map((c) => c.name).toList();
    expect(names, ['apparel', 'Drinks', 'snacks']);
  });

  test('does not leak categories across businesses', () async {
    await db.insert('businesses', {
      'id': 'biz_2',
      'user_id': 'usr_1',
      'name': 'Other Store',
      'type': 'Services',
      'address': '',
      'phone': '',
      'created_at': 1,
    });
    await repo.insert(_category('cat_1', 'Drinks'));
    await repo.insert(_category('cat_2', 'Tools', businessId: 'biz_2'));

    expect((await repo.listForBusiness(_bizId)).single.name, 'Drinks');
    expect((await repo.listForBusiness('biz_2')).single.name, 'Tools');
  });

  test('productCounts tallies each category and omits uncategorized', () async {
    await repo.insert(_category('cat_1', 'Drinks'));
    await repo.insert(_category('cat_2', 'Snacks'));
    await _addProduct(db, id: 'prd_1', categoryId: 'cat_1');
    await _addProduct(db, id: 'prd_2', categoryId: 'cat_1');
    await _addProduct(db, id: 'prd_3', categoryId: 'cat_2');
    await _addProduct(db, id: 'prd_4'); // uncategorized

    final counts = await repo.productCounts(_bizId);
    expect(counts['cat_1'], 2);
    expect(counts['cat_2'], 1);
    expect(counts.containsKey(null), isFalse);
    expect(counts.length, 2);
  });

  test('deleting a category keeps its products and uncategorizes them',
      () async {
    await repo.insert(_category('cat_1', 'Drinks'));
    await _addProduct(db, id: 'prd_1', categoryId: 'cat_1');

    await repo.delete('cat_1');

    // products.category_id is ON DELETE SET NULL — the product must survive.
    final product =
        (await db.query('products', where: 'id = ?', whereArgs: ['prd_1']))
            .single;
    expect(product['category_id'], isNull);
    expect(await repo.listForBusiness(_bizId), isEmpty);
  });

  test('rename writes the new name', () async {
    await repo.insert(_category('cat_1', 'Drinks'));

    await repo.rename(id: 'cat_1', name: 'Beverages');

    expect((await repo.listForBusiness(_bizId)).single.name, 'Beverages');
  });

  test('rename on a deleted category throws instead of silently passing',
      () async {
    await expectLater(
      repo.rename(id: 'cat_gone', name: 'Ghost'),
      throwsA(isA<StateError>()),
    );
  });

  test('nameExists is case-insensitive and scoped to the business', () async {
    await db.insert('businesses', {
      'id': 'biz_2',
      'user_id': 'usr_1',
      'name': 'Other Store',
      'type': 'Services',
      'address': '',
      'phone': '',
      'created_at': 1,
    });
    await repo.insert(_category('cat_1', 'Drinks'));

    expect(await repo.nameExists(businessId: _bizId, name: 'drinks'), isTrue);
    expect(
        await repo.nameExists(businessId: _bizId, name: '  DRINKS  '), isTrue);
    expect(await repo.nameExists(businessId: _bizId, name: 'Snacks'), isFalse);
    // The same name is free in a different business.
    expect(await repo.nameExists(businessId: 'biz_2', name: 'Drinks'), isFalse);
  });

  test('nameExists lets a rename keep its own name', () async {
    await repo.insert(_category('cat_1', 'Drinks'));

    expect(
      await repo.nameExists(
          businessId: _bizId, name: 'Drinks', exceptId: 'cat_1'),
      isFalse,
    );
    expect(
      await repo.nameExists(
          businessId: _bizId, name: 'Drinks', exceptId: 'cat_2'),
      isTrue,
    );
  });
}
