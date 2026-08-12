import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/models/entities.dart';
import 'package:sellora_mobile/data/repositories/product_repository.dart';
import 'package:sellora_mobile/data/repositories/sale_repository.dart';
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

Product _product({
  required String id,
  required String name,
  int stock = 10,
  bool trackStock = true,
  bool active = true,
  String unit = 'pcs',
}) =>
    Product(
      id: id,
      businessId: _bizId,
      categoryId: null,
      name: name,
      description: '',
      sku: '',
      unit: unit,
      price: 50.0,
      stock: stock,
      trackStock: trackStock,
      active: active,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

Future<int> _stockOf(Database db, String id) async {
  final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
  return (rows.single['stock'] as num).toInt();
}

Future<int> _ledgerCount(Database db, String productId) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM stock_ledger WHERE product_id = ?',
    [productId],
  );
  return (rows.first['c'] as int?) ?? 0;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late ProductRepository products;
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
    products = ProductRepository(db);
    sales = SaleRepository(db);
    await _seedBusiness(db);
  });

  tearDown(() async => db.close());

  test('round-trips the new description, unit, and track_stock columns',
      () async {
    await products.insert(_product(
      id: 'prd_1',
      name: 'Water Refill',
      unit: 'gallon',
      trackStock: false,
      stock: 0,
    ));

    final stored = (await products.getById('prd_1'))!;
    expect(stored.unit, 'gallon');
    expect(stored.trackStock, isFalse);
    expect(stored.description, '');

    await products.update(_product(
      id: 'prd_1',
      name: 'Water Refill',
      unit: 'liter',
      trackStock: true,
      stock: 4,
    ));
    final updated = (await products.getById('prd_1'))!;
    expect(updated.unit, 'liter');
    expect(updated.trackStock, isTrue);
    expect(updated.stock, 4);
  });

  test('selling a tracked product decrements stock and writes a ledger row',
      () async {
    await products.insert(_product(id: 'prd_1', name: 'Coffee', stock: 10));

    await sales.recordSale(
      businessId: _bizId,
      lines: [(productId: 'prd_1', name: 'Coffee', qty: 3, unitPrice: 50.0)],
    );

    expect(await _stockOf(db, 'prd_1'), 7);
    // One row for the initial stock, one for the sale.
    expect(await _ledgerCount(db, 'prd_1'), 2);
  });

  test('selling an untracked product touches neither stock nor the ledger',
      () async {
    await products.insert(_product(
      id: 'prd_svc',
      name: 'Delivery Service',
      stock: 0,
      trackStock: false,
    ));

    final saleId = await sales.recordSale(
      businessId: _bizId,
      lines: [
        (
          productId: 'prd_svc',
          name: 'Delivery Service',
          qty: 5,
          unitPrice: 50.0
        )
      ],
    );

    // The sale and its revenue are still recorded in full.
    final sale = (await sales.getById(saleId))!;
    expect(sale.total, 250.0);
    expect(sale.lines.single.qty, 5);

    expect(await _stockOf(db, 'prd_svc'), 0);
    expect(await _ledgerCount(db, 'prd_svc'), 0);
  });

  test('an untracked product is never blocked by insufficient stock', () async {
    await products.insert(_product(
      id: 'prd_svc',
      name: 'Consulting',
      stock: 0,
      trackStock: false,
    ));

    // A tracked product at stock 0 would throw here.
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        (productId: 'prd_svc', name: 'Consulting', qty: 99, unitPrice: 50.0)
      ],
    );
    expect(await _stockOf(db, 'prd_svc'), 0);
  });

  test('a tracked product still rejects overselling, and rolls back', () async {
    await products.insert(_product(id: 'prd_1', name: 'Coffee', stock: 2));

    await expectLater(
      sales.recordSale(
        businessId: _bizId,
        lines: [(productId: 'prd_1', name: 'Coffee', qty: 5, unitPrice: 50.0)],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await _stockOf(db, 'prd_1'), 2);
    final saleRows = await db.rawQuery('SELECT COUNT(*) AS c FROM sales');
    expect(saleRows.first['c'], 0);
  });

  test('a mixed cart decrements only the tracked line', () async {
    await products.insert(_product(id: 'prd_1', name: 'Coffee', stock: 10));
    await products.insert(_product(
      id: 'prd_svc',
      name: 'Delivery',
      stock: 0,
      trackStock: false,
    ));

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        (productId: 'prd_1', name: 'Coffee', qty: 2, unitPrice: 50.0),
        (productId: 'prd_svc', name: 'Delivery', qty: 1, unitPrice: 50.0),
      ],
    );

    expect(await _stockOf(db, 'prd_1'), 8);
    expect(await _stockOf(db, 'prd_svc'), 0);
    expect(await _ledgerCount(db, 'prd_svc'), 0);
  });

  test('low stock ignores untracked products', () async {
    await products.insert(_product(id: 'prd_1', name: 'Coffee', stock: 2));
    await products.insert(_product(
      id: 'prd_svc',
      name: 'Delivery',
      stock: 0,
      trackStock: false,
    ));
    await products.insert(_product(id: 'prd_2', name: 'Tea', stock: 50));

    final low = await products.listLowStock(_bizId);
    expect(low.map((p) => p.id), ['prd_1']);
  });
}
