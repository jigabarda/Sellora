import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The `users` table as shipped in v3/v4 — keyed by email, before usernames.
const _v4Users = '''
CREATE TABLE users (
  id TEXT NOT NULL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''';

/// The `businesses` table as shipped in v3/v4, cascade included. The cascade
/// is the whole point: it is what a careless v5 rebuild would fire.
const _v4Businesses = '''
CREATE TABLE businesses (
  id TEXT NOT NULL PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  address TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
''';

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

/// `sales` and `sale_lines` as shipped up to v5 — before rental days and
/// before discounts. The point of keeping them verbatim is that a real
/// upgrade runs against these, not against the current schema with a few
/// columns removed.
const _v5Sales = '''
CREATE TABLE sales (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  customer_id TEXT,
  total REAL NOT NULL,
  created_at INTEGER NOT NULL
);
''';

const _v5SaleLines = '''
CREATE TABLE sale_lines (
  id TEXT NOT NULL PRIMARY KEY,
  sale_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  name TEXT NOT NULL,
  qty INTEGER NOT NULL,
  unit_price REAL NOT NULL
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

  test('v3 -> v5 adds the product columns and backfills existing rows',
      () async {
    await db.execute(_v4Users);
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

  test('v1 -> v5 upgrades in one step without a duplicate column error',
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
    // v1 predates `users` entirely, so it is created straight in its v5 shape
    // and the email conversion step must not run against it.
    expect(await _columns(db, 'users'), contains('username'));
    expect(await _columns(db, 'users'), isNot(contains('email')));

    // The pre-existing business survives, unowned until someone registers.
    final row = (await db.query('businesses')).single;
    expect(row['name'], 'Store');
    expect(row['user_id'], isNull);
  });

  test(
      'v5 -> v8 adds rentals, discounts and periods without disturbing what '
      'is there', () async {
    await db.execute(_v3Products);
    await db.execute(_v5Sales);
    await db.execute(_v5SaleLines);
    await db.insert('sales', {
      'id': 'sale_1',
      'business_id': 'biz_1',
      'customer_id': null,
      'total': 250.0,
      'created_at': 1,
    });
    await db.insert('sale_lines', {
      'id': 'ln_1',
      'sale_id': 'sale_1',
      'product_id': 'prd_1',
      'name': 'Ice',
      'qty': 5,
      'unit_price': 50.0,
    });

    await SelloraDatabase.migrate(db, 5);

    expect(await _columns(db, 'products'), contains('rental'));
    expect(
      await _columns(db, 'sale_lines'),
      containsAll(['days', 'returned_qty', 'starts_at']),
    );
    expect(await _columns(db, 'sales'), contains('discount'));

    // The defaults are chosen so no row already in the database needs
    // touching: nothing was a rental, everything was for one day, nothing has
    // come back, and nobody was given money off.
    final line = (await db.query('sale_lines')).single;
    expect(line['days'], 1);
    expect(line['returned_qty'], 0);
    // Null, not backfilled: it already means "started when the sale was rung
    // up", which is what a line without dates always meant.
    expect(line['starts_at'], isNull);

    final sale = (await db.query('sales')).single;
    expect(sale['total'], 250.0, reason: 'the money recorded is unchanged');
    expect(sale['discount'], 0);
  });

  test('re-running the v6/v7/v8 steps is a no-op rather than an error',
      () async {
    // The columns are added by asking the database what it already has, so an
    // upgrade that runs twice — a crash mid-migration, a version bumped in
    // two places — must not fail on a duplicate column.
    await db.execute(_v3Products);
    await db.execute(_v5Sales);
    await db.execute(_v5SaleLines);

    await SelloraDatabase.migrate(db, 5);
    await SelloraDatabase.migrate(db, 5);

    expect(await _columns(db, 'sales'), contains('discount'));
    expect(await _columns(db, 'sale_lines'), contains('starts_at'));
  });

  test('v4 -> v9 gives an existing account its recovery columns', () async {
    // The recovery columns land on a `users` table that the v5 step rebuilt
    // from scratch, so this checks the two steps compose rather than the
    // later one quietly finding nothing to alter.
    await db.execute(_v4Users);
    await db.execute(_v4Businesses);
    await db.insert('users', {
      'id': 'usr_1',
      'email': 'james@gmail.com',
      'name': 'James',
      'salt': 'salt',
      'password_hash': 'hash',
      'created_at': 1,
    });

    await SelloraDatabase.migrate(db, 4);

    expect(
      await _columns(db, 'users'),
      containsAll(['username', 'recovery_salt', 'recovery_hash']),
    );

    // The account survives with no code, which is the correct starting state:
    // nobody has been given one, so nobody can reset with one.
    final user = (await db.query('users')).single;
    expect(user['username'], 'james');
    expect(user['recovery_salt'], isNull);
    expect(user['recovery_hash'], isNull);
  });

  test('v2 -> v5 adds the product columns without touching users again',
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

  test('a fresh install already has every v5 column', () async {
    await SelloraDatabase.createSchema(db);

    expect(
      await _columns(db, 'products'),
      containsAll(['description', 'unit', 'track_stock', 'sku', 'category_id']),
    );
    expect(await _columns(db, 'users'), contains('username'));
  });

  group('v4 -> v5 username conversion', () {
    late Directory dir;
    late String path;

    // A real file, not `inMemoryDatabasePath`: this has to close a v4 database
    // and reopen it through the production options to trigger a genuine
    // upgrade, and an in-memory database does not survive the close.
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sellora_migration');
      path = p.join(dir.path, 'sellora.db');
    });

    tearDown(() async => dir.delete(recursive: true));

    Future<Database> seedV4(
      List<({String id, String email})> users,
    ) async {
      final v4 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute(_v4Users);
            await db.execute(_v4Businesses);
          },
        ),
      );
      for (final (index, user) in users.indexed) {
        await v4.insert('users', {
          'id': user.id,
          'email': user.email,
          'name': 'Owner ${user.id}',
          'salt': 'salt',
          'password_hash': 'hash',
          'created_at': index + 1,
        });
        await v4.insert('businesses', {
          'id': 'biz_${user.id}',
          'user_id': user.id,
          'name': 'Store ${user.id}',
          'type': 'Retail Store',
          'address': '',
          'phone': '',
          'created_at': 1,
        });
      }
      await v4.close();
      return databaseFactory.openDatabase(
        path,
        options: SelloraDatabase.openOptions(),
      );
    }

    test('derives the username from the local part of the email', () async {
      final db = await seedV4([(id: 'usr_1', email: 'James.Ivan@Gmail.com')]);
      addTearDown(db.close);

      final user = (await db.query('users')).single;
      expect(user['username'], 'james.ivan');
      expect(user['id'], 'usr_1', reason: 'the account id must be preserved');
      expect(user['password_hash'], 'hash',
          reason: 'credentials must survive the rebuild or nobody can log in');
    });

    test('does not cascade away the businesses it is meant to keep', () async {
      final db = await seedV4([
        (id: 'usr_1', email: 'one@test.com'),
        (id: 'usr_2', email: 'two@test.com'),
      ]);
      addTearDown(db.close);

      // The whole reason foreign keys are disabled for the upgrade: with them
      // on, dropping the old `users` table deletes every row, and the cascade
      // takes each owner's businesses with it.
      final businesses = await db.query('businesses', orderBy: 'id ASC');
      expect(businesses, hasLength(2));
      expect(businesses.first['user_id'], 'usr_1');
    });

    test('suffixes a username when two accounts share a local part', () async {
      final db = await seedV4([
        (id: 'usr_1', email: 'james@gmail.com'),
        (id: 'usr_2', email: 'james@work.com'),
      ]);
      addTearDown(db.close);

      final users = await db.query('users', orderBy: 'created_at ASC');
      expect(users.map((u) => u['username']), ['james', 'james2']);
    });

    test('falls back when an address has no usable local part', () async {
      final db = await seedV4([(id: 'usr_1', email: '!!@test.com')]);
      addTearDown(db.close);

      expect((await db.query('users')).single['username'], 'owner');
    });

    test('leaves foreign keys enforced once the upgrade finishes', () async {
      final db = await seedV4([(id: 'usr_1', email: 'one@test.com')]);
      addTearDown(db.close);

      final pragma = await db.rawQuery('PRAGMA foreign_keys');
      expect(pragma.single.values.first, 1);

      // Proof it is actually enforcing, not just reporting that it is.
      await expectLater(
        db.insert('businesses', {
          'id': 'biz_orphan',
          'user_id': 'usr_missing',
          'name': 'Orphan',
          'type': 'Retail Store',
          'address': '',
          'phone': '',
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
