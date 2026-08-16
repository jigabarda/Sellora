import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/insights/insight.dart';
import 'package:sellora_mobile/data/insights/insights_service.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The clock every test pins. Insights are entirely time-relative, so a real
/// `DateTime.now()` would make half of these pass or fail depending on the day
/// of the week they happened to run.
final now = DateTime(2026, 3, 15, 12);

const bizId = 'biz_1';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late InsightsService insights;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    insights = InsightsService(db);

    await db.insert('users', {
      'id': 'usr_1',
      'username': 'owner',
      'name': 'Owner',
      'salt': 'salt',
      'password_hash': 'hash',
      'created_at': _at(400),
    });
    // Old enough that the profit rule's age gate is satisfied by default;
    // tests that exercise that gate override it.
    await db.insert('businesses', {
      'id': bizId,
      'user_id': 'usr_1',
      'name': 'Test Store',
      'type': 'Retail Store',
      'address': '',
      'phone': '',
      'created_at': _at(365),
    });
  });

  tearDown(() async => db.close());

  // --- 1. Stock run-out ------------------------------------------------------

  group('stock run-out', () {
    test('fires with the right rate and days remaining', () async {
      await _product(db,
          id: 'p1', name: 'Refill', stock: 3, createdDaysAgo: 60);
      // 14 units across 3 separate days, against a 14-day window: exactly
      // 1.0/day, so 3 in stock is 3 days.
      await _sold(db, 'p1', qty: 6, daysAgo: 2);
      await _sold(db, 'p1', qty: 4, daysAgo: 5);
      await _sold(db, 'p1', qty: 4, daysAgo: 9);

      final result = await insights.stockRunOut(bizId, now: now);

      expect(result, hasLength(1));
      expect(result.single.title, 'Refill runs out in about 3 days');
      expect(result.single.detail, contains('1.0 pcs a day'));
      expect(result.single.detail, contains('have 3 left'));
      expect(result.single.severity, InsightSeverity.warning);
    });

    test('stays silent one sale-day below the gate', () async {
      await _product(db,
          id: 'p1', name: 'Refill', stock: 3, createdDaysAgo: 60);
      // Same 14 units, same stock — but concentrated on two days, so there is
      // no rate to extrapolate from. This is the case that matters: without
      // the gate it would confidently predict a run-out from an afternoon.
      await _sold(db, 'p1', qty: 7, daysAgo: 2);
      await _sold(db, 'p1', qty: 7, daysAgo: 5);

      expect(await insights.stockRunOut(bizId, now: now), isEmpty);
    });

    test('escalates to critical inside two days', () async {
      await _product(db,
          id: 'p1', name: 'Refill', stock: 2, createdDaysAgo: 60);
      await _sold(db, 'p1', qty: 6, daysAgo: 2);
      await _sold(db, 'p1', qty: 4, daysAgo: 5);
      await _sold(db, 'p1', qty: 4, daysAgo: 9);

      final result = await insights.stockRunOut(bizId, now: now);
      expect(result.single.severity, InsightSeverity.critical);
    });

    test('says nothing about stock that lasts beyond the horizon', () async {
      await _product(db,
          id: 'p1', name: 'Refill', stock: 100, createdDaysAgo: 60);
      await _sold(db, 'p1', qty: 6, daysAgo: 2);
      await _sold(db, 'p1', qty: 4, daysAgo: 5);
      await _sold(db, 'p1', qty: 4, daysAgo: 9);

      expect(await insights.stockRunOut(bizId, now: now), isEmpty);
    });

    test('measures a new product against its own age, not the window',
        () async {
      // Created 4 days ago and sold 12 units. Over the full 14-day window that
      // reads as 0.86/day and 4 days of cover; against the 4 days it has
      // actually existed it is 3/day and one day of cover. The second is true.
      await _product(db, id: 'p1', name: 'Refill', stock: 3, createdDaysAgo: 4);
      await _sold(db, 'p1', qty: 4, daysAgo: 1);
      await _sold(db, 'p1', qty: 4, daysAgo: 2);
      await _sold(db, 'p1', qty: 4, daysAgo: 3);

      final result = await insights.stockRunOut(bizId, now: now);
      expect(result.single.detail, contains('3.0 pcs a day'));
      expect(result.single.severity, InsightSeverity.critical);
    });

    test('ignores untracked and inactive products', () async {
      await _product(db,
          id: 'svc',
          name: 'Delivery',
          stock: 3,
          createdDaysAgo: 60,
          tracked: false);
      await _product(db,
          id: 'old',
          name: 'Retired',
          stock: 3,
          createdDaysAgo: 60,
          active: false);
      for (final id in ['svc', 'old']) {
        await _sold(db, id, qty: 6, daysAgo: 2);
        await _sold(db, id, qty: 4, daysAgo: 5);
        await _sold(db, id, qty: 4, daysAgo: 9);
      }

      expect(await insights.stockRunOut(bizId, now: now), isEmpty);
    });
  });

  // --- 2. Profit direction ---------------------------------------------------

  group('profit direction', () {
    test('reports the loss and what drove it', () async {
      await _sale(db, id: 's1', total: 605, daysAgo: 2);
      await _expense(db, amount: 8000, category: 'Rent', daysAgo: 3);
      await _expense(db, amount: 5350, category: 'Payroll', daysAgo: 4);
      await _expense(db, amount: 5000, category: 'Supplies', daysAgo: 5);

      final result = await insights.profitDirection(bizId, now: now);

      expect(result.single.severity, InsightSeverity.warning);
      expect(result.single.title, contains('17,745'));
      expect(result.single.detail, contains('18,350'));
      expect(result.single.detail, contains('605'));
      // Only the two largest categories are named — listing all six would be a
      // table, not a sentence.
      expect(result.single.detail, contains('Rent'));
      expect(result.single.detail, contains('Payroll'));
      expect(result.single.detail, isNot(contains('Supplies')));
    });

    test('stays silent for a business younger than the window', () async {
      await db.update('businesses', {'created_at': _at(3)},
          where: 'id = ?', whereArgs: [bizId]);
      await _sale(db, id: 's1', total: 605, daysAgo: 1);

      expect(await insights.profitDirection(bizId, now: now), isEmpty);
    });

    test('stays silent when the window holds nothing at all', () async {
      expect(await insights.profitDirection(bizId, now: now), isEmpty);
    });

    test('omits the prior-week comparison when there is no prior week',
        () async {
      await _sale(db, id: 's1', total: 605, daysAgo: 2);
      final result = await insights.profitDirection(bizId, now: now);
      // "down from ₱0" would read as a collapse when it means "no records".
      expect(result.single.detail, isNot(contains('week before')));
    });

    test('includes the prior week once it has data', () async {
      await _sale(db, id: 's1', total: 605, daysAgo: 2);
      await _sale(db, id: 's2', total: 900, daysAgo: 9);
      final result = await insights.profitDirection(bizId, now: now);
      expect(result.single.detail, contains('900'));
    });
  });

  // --- 3. Day-of-week --------------------------------------------------------

  group('weekday pattern', () {
    test('names the slowest day against the best', () async {
      await _eightWeeksOfSales(db, saturday: 480, tuesday: 0, other: 100);

      final result = await insights.weekdayPattern(bizId, now: now);

      expect(result.single.title, 'Tuesdays are your slowest day');
      expect(result.single.detail, contains('Saturday'));
      expect(result.single.severity, InsightSeverity.info);
    });

    test('stays silent when every day is much the same', () async {
      // 48 sales — well past the volume gate — but a 10% spread. Without the
      // gap gate this would confidently name a "slowest day" from noise.
      await _eightWeeksOfSales(db, saturday: 100, tuesday: 90, other: 95);

      expect(await insights.weekdayPattern(bizId, now: now), isEmpty);
    });

    test('stays silent below the volume gate', () async {
      for (var i = 0; i < 10; i++) {
        await _sale(db, id: 's$i', total: 100, daysAgo: i * 3);
      }
      expect(await insights.weekdayPattern(bizId, now: now), isEmpty);
    });
  });

  // --- 4. Dead stock ---------------------------------------------------------

  group('dead stock', () {
    test('values what is sitting unsold', () async {
      await _product(db,
          id: 'p1', name: 'Old Jug', stock: 5, price: 250, createdDaysAgo: 90);

      final result = await insights.deadStock(bizId, now: now);

      expect(result.single.title, contains("hasn't sold in 45 days"));
      expect(result.single.detail, contains('5 pcs'));
      expect(result.single.detail, contains('1,250'));
    });

    test('stays silent for a product younger than the threshold', () async {
      // Nothing added last week has "stopped" selling.
      await _product(db,
          id: 'p1', name: 'New Jug', stock: 5, price: 250, createdDaysAgo: 10);

      expect(await insights.deadStock(bizId, now: now), isEmpty);
    });

    test('stays silent once it has sold recently', () async {
      await _product(db,
          id: 'p1', name: 'Old Jug', stock: 5, price: 250, createdDaysAgo: 90);
      await _sale(db, id: 's1', total: 250, daysAgo: 3, productId: 'p1');

      expect(await insights.deadStock(bizId, now: now), isEmpty);
    });

    test('ignores a dead product with nothing on the shelf', () async {
      // Zero stock ties up no money, so there is nothing to act on.
      await _product(db,
          id: 'p1', name: 'Old Jug', stock: 0, price: 250, createdDaysAgo: 90);

      expect(await insights.deadStock(bizId, now: now), isEmpty);
    });
  });

  // --- 5. Refund concentration -----------------------------------------------

  group('refund concentration', () {
    test('reports the ratio it measured', () async {
      await _product(db,
          id: 'p1', name: 'Ice Sack', stock: 20, createdDaysAgo: 60);
      for (var i = 0; i < 6; i++) {
        await _sale(db, id: 's$i', total: 120, daysAgo: i + 1, productId: 'p1');
      }
      await _refund(db, id: 'r1', saleId: 's0', amount: 120, daysAgo: 1);
      await _refund(db, id: 'r2', saleId: 's1', amount: 120, daysAgo: 2);

      final result = await insights.refundConcentration(bizId, now: now);

      expect(result.single.title, contains('Ice Sack'));
      expect(result.single.detail, contains('2 of 6 sales'));
      expect(result.single.severity, InsightSeverity.warning);
    });

    test('stays silent one sale below the gate', () async {
      await _product(db,
          id: 'p1', name: 'Ice Sack', stock: 20, createdDaysAgo: 60);
      for (var i = 0; i < 4; i++) {
        await _sale(db, id: 's$i', total: 120, daysAgo: i + 1, productId: 'p1');
      }
      await _refund(db, id: 'r1', saleId: 's0', amount: 120, daysAgo: 1);
      await _refund(db, id: 'r2', saleId: 's1', amount: 120, daysAgo: 2);

      // 2 of 4 is a 50% refund rate and still means nothing.
      expect(await insights.refundConcentration(bizId, now: now), isEmpty);
    });

    test('excludes multi-item sales, which cannot be attributed', () async {
      await _product(db,
          id: 'p1', name: 'Ice Sack', stock: 20, createdDaysAgo: 60);
      await _product(db,
          id: 'p2', name: 'Water', stock: 20, createdDaysAgo: 60);
      for (var i = 0; i < 6; i++) {
        await _sale(db, id: 's$i', total: 200, daysAgo: i + 1, productId: 'p1');
        await db.insert('sale_lines', {
          'id': 'ln_extra_$i',
          'sale_id': 's$i',
          'product_id': 'p2',
          'name': 'Water',
          'qty': 1,
          'unit_price': 80.0,
        });
      }
      await _refund(db, id: 'r1', saleId: 's0', amount: 200, daysAgo: 1);
      await _refund(db, id: 'r2', saleId: 's1', amount: 200, daysAgo: 2);

      // A refund names a sale, not an item. Guessing which of two products was
      // returned would put a quality complaint against the wrong name.
      expect(await insights.refundConcentration(bizId, now: now), isEmpty);
    });
  });

  // --- 6. Quiet customers ----------------------------------------------------

  group('quiet customers', () {
    test('reports a broken rhythm with the gap it measured', () async {
      await _customer(db, id: 'c1', name: 'Aling Nena');
      // Weekly for four visits, then a month of silence.
      for (final daysAgo in [51, 44, 37, 30]) {
        await _sale(db,
            id: 's$daysAgo', total: 100, daysAgo: daysAgo, customerId: 'c1');
      }

      final result = await insights.quietCustomers(bizId, now: now);

      expect(result.single.title, 'Aling Nena has gone quiet');
      expect(result.single.detail, contains('30 days ago'));
      expect(result.single.detail, contains('every 7.0 days'));
    });

    test('stays silent without enough purchases to call it a rhythm', () async {
      await _customer(db, id: 'c1', name: 'Aling Nena');
      for (final daysAgo in [37, 30]) {
        await _sale(db,
            id: 's$daysAgo', total: 100, daysAgo: daysAgo, customerId: 'c1');
      }

      // Two purchases give one gap, which is a coincidence, not a habit.
      expect(await insights.quietCustomers(bizId, now: now), isEmpty);
    });

    test('stays silent inside the floor, however tight the rhythm', () async {
      await _customer(db, id: 'c1', name: 'Daily Buyer');
      for (final daysAgo in [13, 12, 11, 10]) {
        await _sale(db,
            id: 's$daysAgo', total: 100, daysAgo: daysAgo, customerId: 'c1');
      }

      // Averaging a visit a day and silent for ten is ten times the gap, but
      // ten days is not long enough to worry a shopkeeper.
      expect(await insights.quietCustomers(bizId, now: now), isEmpty);
    });

    test('stays silent for a regular who is merely between visits', () async {
      await _customer(db, id: 'c1', name: 'Monthly Buyer');
      for (final daysAgo in [90, 60, 30, 20]) {
        await _sale(db,
            id: 's$daysAgo', total: 100, daysAgo: daysAgo, customerId: 'c1');
      }

      expect(await insights.quietCustomers(bizId, now: now), isEmpty);
    });
  });

  // --- Aggregation -----------------------------------------------------------

  test('generate returns worst-first', () async {
    await _product(db, id: 'p1', name: 'Refill', stock: 2, createdDaysAgo: 60);
    await _sold(db, 'p1', qty: 6, daysAgo: 2);
    await _sold(db, 'p1', qty: 4, daysAgo: 5);
    await _sold(db, 'p1', qty: 4, daysAgo: 9);
    await _product(db,
        id: 'p2', name: 'Old Jug', stock: 5, price: 250, createdDaysAgo: 90);

    final result = await insights.generate(bizId, now: now);

    expect(result.first.severity, InsightSeverity.critical);
    expect(result.last.severity, InsightSeverity.info);
  });

  test('a business with no records produces nothing', () async {
    expect(await insights.generate(bizId, now: now), isEmpty);
  });
}

// --- fixtures ----------------------------------------------------------------

int _at(int daysAgo) =>
    now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

Future<void> _product(
  Database db, {
  required String id,
  required String name,
  required int stock,
  required int createdDaysAgo,
  double price = 25.0,
  bool tracked = true,
  bool active = true,
}) async {
  await db.insert('products', {
    'id': id,
    'business_id': bizId,
    'category_id': null,
    'name': name,
    'description': '',
    'sku': '',
    'unit': 'pcs',
    'price': price,
    'stock': stock,
    'track_stock': tracked ? 1 : 0,
    'active': active ? 1 : 0,
    'created_at': _at(createdDaysAgo),
  });
}

/// A sale plus its ledger row, the pair `SaleRepository.recordSale` writes.
Future<void> _sold(
  Database db,
  String productId, {
  required int qty,
  required int daysAgo,
}) async {
  await db.insert('stock_ledger', {
    'id': 'stk_${productId}_$daysAgo',
    'business_id': bizId,
    'product_id': productId,
    'delta': -qty,
    'reason': 'sale',
    'ref_id': null,
    'note': '',
    'at': _at(daysAgo),
  });
}

Future<void> _sale(
  Database db, {
  required String id,
  required double total,
  required int daysAgo,
  String? productId,
  String? customerId,
  DateTime? on,
}) async {
  await db.insert('sales', {
    'id': id,
    'business_id': bizId,
    'customer_id': customerId,
    'total': total,
    'created_at': on?.millisecondsSinceEpoch ?? _at(daysAgo),
  });
  if (productId != null) {
    // `recordSale` snapshots the product's name onto the line, and the refund
    // rule reads it back. A placeholder here would let a naming bug through.
    final product = await db.query('products',
        columns: ['name'], where: 'id = ?', whereArgs: [productId], limit: 1);
    await db.insert('sale_lines', {
      'id': 'ln_$id',
      'sale_id': id,
      'product_id': productId,
      'name': product.isEmpty ? productId : product.first['name'],
      'qty': 1,
      'unit_price': total,
    });
  }
}

Future<void> _expense(
  Database db, {
  required double amount,
  required String category,
  required int daysAgo,
}) async {
  await db.insert('expenses', {
    'id': 'exp_${category}_$daysAgo',
    'business_id': bizId,
    'amount': amount,
    'category': category,
    'note': '',
    'at': _at(daysAgo),
  });
}

Future<void> _refund(
  Database db, {
  required String id,
  required String saleId,
  required double amount,
  required int daysAgo,
}) async {
  await db.insert('refunds', {
    'id': id,
    'business_id': bizId,
    'sale_id': saleId,
    'amount': amount,
    'note': '',
    'restock': 0,
    'at': _at(daysAgo),
  });
}

Future<void> _customer(
  Database db, {
  required String id,
  required String name,
}) async {
  await db.insert('customers', {
    'id': id,
    'business_id': bizId,
    'name': name,
    'phone': '',
    'email': '',
    'notes': '',
    'created_at': _at(120),
  });
}

/// Eight weeks of sales with a controllable weekday shape, so the pattern rule
/// has a real distribution to find rather than a hand-picked pair of numbers.
Future<void> _eightWeeksOfSales(
  Database db, {
  required double saturday,
  required double tuesday,
  required double other,
}) async {
  final start = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 8 * 7));
  for (var i = 0; i < 8 * 7; i++) {
    final day = start.add(Duration(days: i));
    final amount = switch (day.weekday) {
      DateTime.saturday => saturday,
      DateTime.tuesday => tuesday,
      _ => other,
    };
    if (amount <= 0) continue;
    await _sale(
      db,
      id: 'sale_$i',
      total: amount,
      daysAgo: 0,
      on: DateTime(day.year, day.month, day.day, 12),
    );
  }
}
