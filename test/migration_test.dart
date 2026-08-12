import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The `businesses` table as shipped in v1 — before `user_id` existed.
const _v1Businesses = '''
CREATE TABLE businesses (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  address TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
''';

/// The `products` table as shipped in v2/v3 — before description/unit/track_stock.
const _v3Products = '''
CREATE TABLE products (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  category_id TEXT,
  name TEXT NOT NULL,
  sku TEXT NOT NULL DEFAULT '',
  price REAL NOT NULL,
  stock INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
''';

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name']! as String).toSet();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  // Foreign keys stay off here: these tests build partial historical schemas
  // where the referenced tables do not all exist yet.
  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });

  tearDown(() async => db.close());

  test('v3 -> v4 adds the product columns and backfills existing rows',
      () async {
    await db.execute(_v3Products);
    await db.insert('products', {
      'id': 'prd_1',
      'business_id': 'biz_1',
      'name': 'Coffee',
      'sku': 'C-1',
      'price': 50.0,
      'stock': 7,
      'active': 1,
      'created_at': 1,
    });

    await SelloraDatabase.migrate(db, 3);

    expect(
      await _columns(db, 'products'),
      containsAll(['description', 'unit', 'track_stock']),
    );

    // An existing product must keep its data and pick up sensible defaults:
    // it was tracking stock before the flag existed, so it still does.
    final row =
        (await db.query('products', where: 'id = ?', whereArgs: ['prd_1']))
            .single;
    expect(row['name'], 'Coffee');
    expect(row['stock'], 7);
    expect(row['description'], '');
    expect(row['unit'], 'pcs');
    expect(row['track_stock'], 1);
  });

  test('v1 -> v4 upgrades in one step without a duplicate column error',
      () async {
    // v1 had businesses only; the operational tables arrived in v2.
    await db.execute(_v1Businesses);
    await db.insert('businesses', {
      'id': 'biz_1',
      'name': 'Store',
      'type': 'Retail Store',
      'address': '',
      'phone': '',
      'created_at': 1,
    });

    await SelloraDatabase.migrate(db, 1);

    // The v2 step creates `products` already carrying the v4 columns, so the
    // v4 step must not ALTER them in again.
    expect(
      await _columns(db, 'products'),
      containsAll(['description', 'unit', 'track_stock']),
    );
    expect(await _columns(db, 'businesses'), contains('user_id'));
    expect(await _columns(db, 'users'), contains('email'));

    // The pre-existing business survives, unowned until someone registers.
    final row = (await db.query('businesses')).single;
    expect(row['name'], 'Store');
    expect(row['user_id'], isNull);
  });

  test('v2 -> v4 adds the product columns without touching users again',
      () async {
    await db.execute(_v1Businesses);
    await db.execute(_v3Products);

    await SelloraDatabase.migrate(db, 2);

    expect(
      await _columns(db, 'products'),
      containsAll(['description', 'unit', 'track_stock']),
    );
    expect(await _columns(db, 'businesses'), contains('user_id'));
  });

  test('a fresh install already has every v4 column', () async {
    await SelloraDatabase.createSchema(db);

    expect(
      await _columns(db, 'products'),
      containsAll(['description', 'unit', 'track_stock', 'sku', 'category_id']),
    );
  });
}
