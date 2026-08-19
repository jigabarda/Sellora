import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/repositories/expense_repository.dart';
import 'package:sellora_mobile/data/repositories/sale_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The queries behind the reports export and its trend.
///
/// Worth their own tests because every one of them decides what lands in a
/// document someone may hand to a bookkeeper: a row on the wrong side of a
/// boundary is a wrong total in somebody's books.

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

/// Inserts a sale directly, so a test can place it at an exact instant without
/// going through stock checks.
Future<void> _sale(
  Database db,
  String id,
  DateTime at,
  double total, {
  List<({String name, int qty, double price})> lines = const [],
}) async {
  await db.insert('sales', {
    'id': id,
    'business_id': _bizId,
    'customer_id': null,
    'total': total,
    'created_at': at.millisecondsSinceEpoch,
  });
  var n = 0;
  for (final l in lines) {
    // sale_lines.product_id is a real foreign key, so the product has to exist
    // before the line that points at it.
    await db.insert(
      'products',
      {
        'id': 'prd_${l.name}',
        'business_id': _bizId,
        'category_id': null,
        'name': l.name,
        'description': '',
        'sku': '',
        'unit': 'pcs',
        'price': l.price,
        'stock': 0,
        'track_stock': 0,
        'active': 1,
        'created_at': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.insert('sale_lines', {
      'id': '${id}_ln${n++}',
      'sale_id': id,
      'product_id': 'prd_${l.name}',
      'name': l.name,
      'qty': l.qty,
      'unit_price': l.price,
    });
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SaleRepository sales;
  late ExpenseRepository expenses;

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
    expenses = ExpenseRepository(db);
    await _seedBusiness(db);
  });

  tearDown(() async => db.close());

  group('listBetween', () {
    test('takes the first instant of the range and drops the last', () async {
      final from = DateTime(2026, 8, 10);
      final toExclusive = DateTime(2026, 8, 12);

      await _sale(db, 'before', from.subtract(const Duration(minutes: 1)), 10);
      await _sale(db, 'first', from, 20);
      await _sale(db, 'inside', DateTime(2026, 8, 11, 13), 30);
      await _sale(db, 'last', toExclusive.subtract(const Duration(minutes: 1)), 40);
      await _sale(db, 'after', toExclusive, 50);

      final got = await sales.listBetween(_bizId, from, toExclusive);
      expect(got.map((s) => s.id), ['first', 'inside', 'last']);
    });

    test('gives every sale its own lines', () async {
      final from = DateTime(2026, 8, 1);
      final to = DateTime(2026, 9, 1);

      await _sale(db, 'sal_a', DateTime(2026, 8, 2), 50, lines: [
        (name: 'Refill', qty: 2, price: 25),
      ]);
      await _sale(db, 'sal_b', DateTime(2026, 8, 3), 145, lines: [
        (name: 'Ice', qty: 1, price: 120),
        (name: 'Refill', qty: 1, price: 25),
      ]);

      final got = await sales.listBetween(_bizId, from, to);
      // The lines come back in one query and are grouped in Dart; this is what
      // proves the grouping did not cross-contaminate the two sales.
      expect(got.firstWhere((s) => s.id == 'sal_a').lines.length, 1);
      expect(got.firstWhere((s) => s.id == 'sal_b').lines.length, 2);
      expect(
        got.firstWhere((s) => s.id == 'sal_b').lines.map((l) => l.name).toSet(),
        {'Ice', 'Refill'},
      );
    });

    test('is not capped the way the screen listing is', () async {
      final from = DateTime(2026, 8, 1);
      for (var i = 0; i < 60; i++) {
        await _sale(db, 'sal_$i', DateTime(2026, 8, 1, 8, i), 10);
      }
      // listRecent stops at 50 by design. An export that quietly did the same
      // would be wrong by ten sales and say nothing.
      final got = await sales.listBetween(_bizId, from, DateTime(2026, 9, 1));
      expect(got.length, 60);
    });
  });

  group('revenueByDay', () {
    test('buckets by the owner\'s local midnight, not UTC', () async {
      final from = DateTime(2026, 8, 10);
      final to = DateTime(2026, 8, 13);

      // Late evening and just after midnight: in Manila these are different
      // days, and grouping the epoch in SQL would slide them together.
      await _sale(db, 'evening', DateTime(2026, 8, 10, 23, 30), 100);
      await _sale(db, 'after_midnight', DateTime(2026, 8, 11, 0, 15), 40);
      await _sale(db, 'same_day', DateTime(2026, 8, 11, 9, 0), 60);

      final got = await sales.revenueByDay(_bizId, from, to);
      expect(got[DateTime(2026, 8, 10)], 100);
      expect(got[DateTime(2026, 8, 11)], 100);
    });

    test('omits days with no sales rather than inventing zeroes', () async {
      await _sale(db, 'only', DateTime(2026, 8, 10, 10), 25);
      final got = await sales.revenueByDay(
          _bizId, DateTime(2026, 8, 1), DateTime(2026, 9, 1));
      // The chart fills the gaps; the query reports what happened.
      expect(got.keys.toList(), [DateTime(2026, 8, 10)]);
    });
  });

  group('productPerformance', () {
    test('sums quantity and revenue per product, dearest first', () async {
      final from = DateTime(2026, 8, 1);
      final to = DateTime(2026, 9, 1);

      await _sale(db, 'sal_a', DateTime(2026, 8, 2), 50, lines: [
        (name: 'Refill', qty: 2, price: 25),
      ]);
      await _sale(db, 'sal_b', DateTime(2026, 8, 3), 145, lines: [
        (name: 'Refill', qty: 1, price: 25),
        (name: 'Ice', qty: 1, price: 120),
      ]);

      final got = await sales.productPerformance(_bizId, from, to);
      expect(got.map((p) => p.name), ['Ice', 'Refill']);
      expect(got.firstWhere((p) => p.name == 'Refill').qty, 3);
      expect(got.firstWhere((p) => p.name == 'Refill').revenue, 75);
    });

    test('ignores sales outside the range', () async {
      await _sale(db, 'old', DateTime(2026, 7, 30), 25, lines: [
        (name: 'Refill', qty: 1, price: 25),
      ]);
      final got = await sales.productPerformance(
          _bizId, DateTime(2026, 8, 1), DateTime(2026, 9, 1));
      expect(got, isEmpty);
    });
  });

  test('expenses listBetween respects the same half-open range', () async {
    Future<void> spend(String id, DateTime at, double amount) => db.insert(
          'expenses',
          {
            'id': id,
            'business_id': _bizId,
            'amount': amount,
            'category': 'Delivery',
            'note': '',
            'at': at.millisecondsSinceEpoch,
          },
        );

    final from = DateTime(2026, 8, 10);
    final toExclusive = DateTime(2026, 8, 12);
    await spend('before', from.subtract(const Duration(minutes: 1)), 5);
    await spend('inside', DateTime(2026, 8, 11), 15);
    await spend('after', toExclusive, 25);

    final got = await expenses.listBetween(_bizId, from, toExclusive);
    expect(got.map((e) => e.id), ['inside']);
  });
}
