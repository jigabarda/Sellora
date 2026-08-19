import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/repositories/sale_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A discount is the one number in a sale that is agreed rather than
/// calculated, which is exactly why it has to be recorded rather than inferred.
/// `total` stays what the customer paid — every report reads it — and
/// `discount` remembers what was given up, so a receipt can still show the
/// arithmetic a year later.

const _bizId = 'biz_1';

Future<void> _seed(Database db) async {
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
    'name': 'Sari-sari',
    'type': 'Retail',
    'address': '',
    'phone': '',
    'created_at': 1,
  });
  await db.insert('products', {
    'id': 'ice',
    'business_id': _bizId,
    'category_id': null,
    'name': 'Ice',
    'description': '',
    'sku': '',
    'unit': 'pcs',
    'price': 100,
    'stock': 100,
    'track_stock': 1,
    'rental': 0,
    'active': 1,
    'created_at': 1,
  });
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SaleRepository sales;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    sales = SaleRepository(db);
    await _seed(db);
  });

  tearDown(() async => db.close());

  Future<String> sell({required int qty, double discount = 0}) =>
      sales.recordSale(
        businessId: _bizId,
        discount: discount,
        lines: [
          (productId: 'ice', name: 'Ice', qty: qty, unitPrice: 100, days: 1),
        ],
      );

  test('the total recorded is what the customer paid', () async {
    final id = await sell(qty: 5, discount: 50);
    final sale = await sales.getById(id);

    expect(sale!.total, 450, reason: '500 less 50');
    expect(sale.discount, 50);
    expect(sale.subtotal, 500, reason: 'derived back from total + discount');
  });

  test('no discount means no discount, and the total is untouched', () async {
    final sale = await sales.getById(await sell(qty: 3));
    expect(sale!.total, 300);
    expect(sale.discount, 0);
  });

  test('a discount larger than the sale is clamped, not refused', () async {
    // A typo at the counter should bring the total to zero at worst. Throwing
    // would lose the sale that is already half rung up.
    final sale = await sales.getById(await sell(qty: 1, discount: 9999));
    expect(sale!.total, 0);
    expect(sale.discount, 100);
  });

  test('a negative discount is ignored rather than added on', () async {
    final sale = await sales.getById(await sell(qty: 2, discount: -50));
    expect(sale!.total, 200);
    expect(sale.discount, 0);
  });

  test('the discount does not change what leaves the shelf', () async {
    await sell(qty: 10, discount: 400);
    final rows =
        await db.query('products', where: 'id = ?', whereArgs: ['ice']);
    expect((rows.single['stock'] as num).toInt(), 90);
  });

  test('takings for the day are the discounted totals', () async {
    await sell(qty: 5, discount: 100);
    await sell(qty: 5);

    final all = await sales.listRecent(_bizId);
    final takings = all.fold<double>(0, (sum, s) => sum + s.total);
    expect(takings, 900, reason: '400 + 500, not 1000');
  });

  test('a discount applies to a rental after the days are counted', () async {
    await db.insert('products', {
      'id': 'chair',
      'business_id': _bizId,
      'category_id': null,
      'name': 'Chair',
      'description': '',
      'sku': '',
      'unit': 'pcs',
      'price': 10,
      'stock': 50,
      'track_stock': 1,
      'rental': 1,
      'active': 1,
      'created_at': 1,
    });

    // Twenty chairs, ten pesos a day, three days is six hundred; a hundred off
    // makes five hundred. Discounting the day rate instead would be a very
    // different number.
    final id = await sales.recordSale(
      businessId: _bizId,
      discount: 100,
      lines: [
        (productId: 'chair', name: 'Chair', qty: 20, unitPrice: 10, days: 3),
      ],
    );

    final sale = await sales.getById(id);
    expect(sale!.subtotal, 600);
    expect(sale.total, 500);
  });
}
