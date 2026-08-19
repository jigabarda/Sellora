import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/repositories/sale_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// What separates a rental from a sale is not the arithmetic, it is the stock:
/// a sale's decrement is permanent and a rental's is not. Get that wrong and a
/// shop that rents twenty chairs every weekend owns none by the end of the
/// month, according to the app. These tests exist to keep that from happening
/// quietly.

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
    'name': 'Party Rentals',
    'type': 'Rental Business',
    'address': '',
    'phone': '',
    'created_at': 1,
  });
}

Future<void> _product(
  Database db, {
  required String id,
  required String name,
  double price = 10,
  int stock = 50,
  bool rental = true,
  bool trackStock = true,
}) =>
    db.insert('products', {
      'id': id,
      'business_id': _bizId,
      'category_id': null,
      'name': name,
      'description': '',
      'sku': '',
      'unit': 'pcs',
      'price': price,
      'stock': stock,
      'track_stock': trackStock ? 1 : 0,
      'rental': rental ? 1 : 0,
      'active': 1,
      'created_at': 1,
    });

Future<int> _stockOf(Database db, String id) async {
  final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
  return (rows.single['stock'] as num).toInt();
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
    await _seedBusiness(db);
  });

  tearDown(() async => db.close());

  test('a rental is priced per day, so days multiply the total', () async {
    await _product(db, id: 'chair', name: 'Chair', price: 10, stock: 50);

    // The example that started this: twenty chairs at ten pesos for three days.
    final saleId = await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 20, unitPrice: 10, days: 3),
      ],
    );

    final sale = await sales.getById(saleId);
    expect(sale!.total, 600);
    expect(sale.lines.single.days, 3);
    expect(sale.lines.single.total, 600);
  });

  test('a sold line is one day, and the arithmetic does not change', () async {
    await _product(db, id: 'water', name: 'Water', price: 25, rental: false);

    final saleId = await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'water', name: 'Water', qty: 2, unitPrice: 25),
      ],
    );

    expect((await sales.getById(saleId))!.total, 50);
  });

  test('renting takes the stock off the shelf', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 20, unitPrice: 10, days: 3),
      ],
    );

    expect(await _stockOf(db, 'chair'), 30);
  });

  test('returning puts it back — the whole point of a rental', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 20, unitPrice: 10, days: 3),
      ],
    );
    expect(await _stockOf(db, 'chair'), 30);

    final out = await sales.listOutstandingRentals(_bizId);
    await sales.recordRentalReturn(
      businessId: _bizId,
      lineId: out.single.lineId,
      qty: 20,
    );

    // Back where it started. A sale would have left it at 30 forever.
    expect(await _stockOf(db, 'chair'), 50);
    expect(await sales.listOutstandingRentals(_bizId), isEmpty);
  });

  test('a partial return is allowed and leaves the rest outstanding', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 20, unitPrice: 10),
      ],
    );

    final out = await sales.listOutstandingRentals(_bizId);
    await sales.recordRentalReturn(
      businessId: _bizId,
      lineId: out.single.lineId,
      qty: 19,
    );

    expect(await _stockOf(db, 'chair'), 49);
    final still = await sales.listOutstandingRentals(_bizId);
    expect(still.single.outstanding, 1);
  });

  test('returning more than is out is refused', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 5, unitPrice: 10),
      ],
    );

    final out = await sales.listOutstandingRentals(_bizId);
    await expectLater(
      sales.recordRentalReturn(
          businessId: _bizId, lineId: out.single.lineId, qty: 6),
      throwsA(isA<StateError>()),
    );
    // And nothing moved.
    expect(await _stockOf(db, 'chair'), 45);
  });

  test('something sold cannot be returned as a rental', () async {
    await _product(db, id: 'water', name: 'Water', rental: false, stock: 10);
    final saleId = await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'water', name: 'Water', qty: 2, unitPrice: 25),
      ],
    );

    final sale = await sales.getById(saleId);
    await expectLater(
      sales.recordRentalReturn(
        businessId: _bizId,
        lineId: sale!.lines.single.id,
        qty: 1,
      ),
      // Refunds are the path for a sale; conflating the two would restock
      // without any of the money being reconsidered.
      throwsA(isA<StateError>()),
    );
    expect(await _stockOf(db, 'water'), 8);
  });

  test('only rentals appear as outstanding', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await _product(db, id: 'water', name: 'Water', rental: false, stock: 10);

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 4, unitPrice: 10, days: 2),
        const SaleLineDraft(
            productId: 'water', name: 'Water', qty: 1, unitPrice: 25),
      ],
    );

    final out = await sales.listOutstandingRentals(_bizId);
    expect(out.length, 1);
    expect(out.single.productName, 'Chair');
  });

  test('the ledger tells a rental going out from a sale', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await _product(db, id: 'water', name: 'Water', rental: false, stock: 10);

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 4, unitPrice: 10, days: 2),
        const SaleLineDraft(
            productId: 'water', name: 'Water', qty: 1, unitPrice: 25),
      ],
    );
    final out = await sales.listOutstandingRentals(_bizId);
    await sales.recordRentalReturn(
        businessId: _bizId, lineId: out.single.lineId, qty: 4);

    final reasons = (await db.query('stock_ledger', orderBy: 'at ASC'))
        .map((r) => '${r['reason']}:${r['delta']}')
        .toList();

    expect(
        reasons, containsAll(['rental_out:-4', 'sale:-1', 'rental_return:4']));
  });

  test('an untracked rental still stops being outstanding', () async {
    // A sound system with no inventory count: there is no shelf to put it back
    // on, but it must still stop showing as out with a customer.
    await _product(db, id: 'sound', name: 'Sound System', trackStock: false);

    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'sound',
            name: 'Sound System',
            qty: 1,
            unitPrice: 500,
            days: 2),
      ],
    );

    final out = await sales.listOutstandingRentals(_bizId);
    await sales.recordRentalReturn(
        businessId: _bizId, lineId: out.single.lineId, qty: 1);

    expect(await sales.listOutstandingRentals(_bizId), isEmpty);
  });

  test('a stated start date drives the due date, not the till time', () async {
    // A booking written up on Friday for chairs going out on Saturday is due
    // back on the Tuesday, not the Monday. Before start dates existed this
    // was always measured from when the sale was rung up.
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        SaleLineDraft(
          productId: 'chair',
          name: 'Chair',
          qty: 20,
          unitPrice: 10,
          days: 3,
          startsAt: DateTime(2026, 8, 22),
        ),
      ],
    );

    final rental = (await sales.listOutstandingRentals(_bizId)).single;
    expect(rental.rentedAt, DateTime(2026, 8, 22));
    expect(rental.dueAt, DateTime(2026, 8, 25));
  });

  test('a booking that has not started yet is not overdue', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        SaleLineDraft(
          productId: 'chair',
          name: 'Chair',
          qty: 4,
          unitPrice: 10,
          days: 2,
          startsAt: DateTime(2030, 1, 10),
        ),
      ],
    );

    final rental = (await sales.listOutstandingRentals(_bizId)).single;
    expect(rental.isOverdue(DateTime(2030, 1, 11)), isFalse);
    expect(rental.isOverdue(DateTime(2030, 1, 13)), isTrue);
  });

  test('a rental with no stated period still starts when it was rung up',
      () async {
    // Every rental recorded before dates existed is this case, and it has to
    // keep meaning what it meant.
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    final before = DateTime.now();
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 1, unitPrice: 10, days: 2),
      ],
    );

    final rental = (await sales.listOutstandingRentals(_bizId)).single;
    expect(
      rental.rentedAt.isBefore(before.subtract(const Duration(seconds: 5))),
      isFalse,
    );
    expect(rental.dueAt.difference(rental.rentedAt).inDays, 2);
  });

  test('a sold line is given no period at all', () async {
    // Otherwise it would sit in front of the return screen's query looking
    // like something a customer still has.
    await _product(db, id: 'water', name: 'Water', rental: false, stock: 10);
    final saleId = await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'water', name: 'Water', qty: 2, unitPrice: 25),
      ],
    );

    final rows =
        await db.query('sale_lines', where: 'sale_id = ?', whereArgs: [saleId]);
    expect(rows.single['starts_at'], isNull);
  });

  test('due date follows the days agreed', () async {
    await _product(db, id: 'chair', name: 'Chair', stock: 50);
    await sales.recordSale(
      businessId: _bizId,
      lines: [
        const SaleLineDraft(
            productId: 'chair', name: 'Chair', qty: 1, unitPrice: 10, days: 3),
      ],
    );

    final rental = (await sales.listOutstandingRentals(_bizId)).single;
    expect(rental.dueAt.difference(rental.rentedAt).inDays, 3);
    expect(
        rental.isOverdue(rental.dueAt.add(const Duration(hours: 1))), isTrue);
    expect(rental.isOverdue(rental.dueAt.subtract(const Duration(hours: 1))),
        isFalse);
  });
}
