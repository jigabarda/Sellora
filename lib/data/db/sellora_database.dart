import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All reads/writes work offline.
class SelloraDatabase {
  SelloraDatabase._();

  static const _fileName = 'sellora.db';
  static const _version = 4;

  static Future<Database> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);

    return openDatabase(
      path,
      version: _version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => migrate(db, oldVersion),
    );
  }

  /// Brings a database created by an older release up to [_version].
  ///
  /// Public so tests can drive it against a hand-built old schema; there is no
  /// other way to exercise an upgrade path without an on-device file.
  static Future<void> migrate(Database db, int oldVersion) async {
    if (oldVersion < 2) {
      await _createOperationalTables(db);
    }
    if (oldVersion < 3) {
      await _createUsers(db);
      await db.execute(
        'ALTER TABLE businesses ADD COLUMN user_id TEXT REFERENCES users(id) ON DELETE CASCADE',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_businesses_user ON businesses(user_id);',
      );
    }
    // Guarded on oldVersion >= 2: anything older just had `products` created
    // above by `_createOperationalTables`, which already declares these
    // columns. ALTERing again would fail on a duplicate column.
    if (oldVersion >= 2 && oldVersion < 4) {
      await db.execute(
        "ALTER TABLE products ADD COLUMN description TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE products ADD COLUMN unit TEXT NOT NULL DEFAULT 'pcs'",
      );
      await db.execute(
        'ALTER TABLE products ADD COLUMN track_stock INTEGER NOT NULL DEFAULT 1',
      );
    }
  }

  /// Builds the full schema on a fresh database.
  ///
  /// Public so tests can stand up an in-memory copy without going through
  /// the on-device file path.
  static Future<void> createSchema(Database db) async {
    await _createUsers(db);
    await _createBusinesses(db);
    await _createOperationalTables(db);
  }

  static Future<void> _createUsers(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS users (
  id TEXT NOT NULL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''');
  }

  static Future<void> _createBusinesses(Database db) async {
    await db.execute('''
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
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_businesses_user ON businesses(user_id);',
    );
  }

  static Future<void> _createOperationalTables(Database db) async {
    await db.execute('''
CREATE TABLE categories (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
''');

    await db.execute('''
CREATE TABLE products (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  category_id TEXT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sku TEXT NOT NULL DEFAULT '',
  unit TEXT NOT NULL DEFAULT 'pcs',
  price REAL NOT NULL,
  stock INTEGER NOT NULL DEFAULT 0,
  track_stock INTEGER NOT NULL DEFAULT 1,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
);
''');

    await db.execute('''
CREATE TABLE customers (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
''');

    await db.execute('''
CREATE TABLE sales (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  customer_id TEXT,
  total REAL NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
  FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
);
''');

    await db.execute('''
CREATE TABLE sale_lines (
  id TEXT NOT NULL PRIMARY KEY,
  sale_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  name TEXT NOT NULL,
  qty INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
);
''');

    await db.execute('''
CREATE TABLE stock_ledger (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  ref_id TEXT,
  note TEXT NOT NULL DEFAULT '',
  at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
);
''');

    await db.execute('''
CREATE TABLE expenses (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  amount REAL NOT NULL,
  category TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
''');

    await db.execute('''
CREATE TABLE refunds (
  id TEXT NOT NULL PRIMARY KEY,
  business_id TEXT NOT NULL,
  sale_id TEXT,
  amount REAL NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  restock INTEGER NOT NULL DEFAULT 0,
  at INTEGER NOT NULL,
  FOREIGN KEY (business_id) REFERENCES businesses(id) ON DELETE CASCADE,
  FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
);
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_business ON products(business_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_business_created ON sales(business_id, created_at);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ledger_business_at ON stock_ledger(business_id, at);',
    );
    // No index on `businesses` here. This runs for a v1 install before the
    // v3 step adds `businesses.user_id`, so indexing that column at this
    // point fails with "no such column". It belongs to whoever owns the
    // table: `_createBusinesses` on a fresh install, the v3 step on an
    // upgrade.
  }
}
