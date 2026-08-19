import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All reads/writes work offline.
class SelloraDatabase {
  SelloraDatabase._();

  static const _fileName = 'sellora.db';
  static const _version = 6;

  static Future<Database> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    return databaseFactory.openDatabase(path, options: openOptions());
  }

  /// How the app opens its database.
  ///
  /// Extracted so the migration test can upgrade a real file through the exact
  /// production path. Driving [migrate] directly cannot prove the upgrade is
  /// safe, because the pragma sequence below is the entire safety mechanism.
  static OpenDatabaseOptions openOptions() {
    return OpenDatabaseOptions(
      version: _version,
      // Foreign keys are deliberately OFF here and switched back ON in
      // `onOpen`.
      //
      // Migrations that change a table's shape have to rebuild it, and with
      // enforcement on, `DROP TABLE users` performs an implicit delete of
      // every row — which fires `businesses.user_id ON DELETE CASCADE` and
      // takes the user's entire dataset with it. SQLite's own documented
      // rebuild procedure requires the pragma off for exactly this reason,
      // and it cannot be toggled from inside `onUpgrade`, because sqflite runs
      // that in a transaction where the statement is silently a no-op. The
      // window is only ever open during create and upgrade; the app itself
      // never sees an unenforced database.
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, version) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => migrate(db, oldVersion),
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
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
    // Guarded on oldVersion >= 3 for the same reason as above: a database
    // older than that had `users` created by `_createUsers` a moment ago,
    // which already declares `username` and has no `email` to convert.
    if (oldVersion >= 3 && oldVersion < 5) {
      await _replaceUserEmailsWithUsernames(db);
    }
    // Rentals. Defaults are chosen so every row already in the database is
    // correct without being touched: nothing was a rental, everything was for
    // one day, and nothing has come back because nothing went out.
    if (oldVersion < 6) {
      await _addColumn(db, 'products', 'rental', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumn(db, 'sale_lines', 'days', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumn(
          db, 'sale_lines', 'returned_qty', 'INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// Adds a column unless the table already has it, or does not exist at all.
  ///
  /// The steps above guard themselves with version ranges, which works but has
  /// to reason about which earlier step already created the table with the
  /// column in it — that is the sort of bookkeeping that goes wrong quietly
  /// three releases later. Asking the database what it actually has is both
  /// shorter and idempotent: re-running a step is a no-op rather than a
  /// duplicate-column failure.
  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (tables.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((c) => c['name'] == column)) return;

    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// Rebuilds `users` so accounts are identified by a username instead of an
  /// email address, deriving each existing username from the local part of the
  /// address it replaces.
  ///
  /// A rebuild is unavoidable: `email` is `NOT NULL UNIQUE`, and SQLite cannot
  /// drop a column carrying a unique constraint. The create/copy/drop/rename
  /// order matters — dropping the old table only after the new one is
  /// populated, and renaming last, is what leaves `businesses.user_id`
  /// pointing at a table that still exists under the name its foreign key
  /// declares. Requires foreign keys to be off; see [open].
  static Future<void> _replaceUserEmailsWithUsernames(Database db) async {
    final existing = await db.query('users', orderBy: 'created_at ASC');

    await _createUsers(db, table: 'users_new');

    // Two accounts can easily share a local part — james@gmail.com and
    // james@work.com both want "james" — so the first one registered keeps it
    // and the rest are suffixed. Ordering by created_at makes which is which
    // deterministic rather than dependent on row order.
    final taken = <String>{};
    for (final row in existing) {
      final username = _uniqueUsername(
        usernameFromEmail(row['email'] as String?),
        taken,
      );
      taken.add(username);
      await db.insert('users_new', {
        'id': row['id'],
        'username': username,
        'name': row['name'],
        'salt': row['salt'],
        'password_hash': row['password_hash'],
        'created_at': row['created_at'],
      });
    }

    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_new RENAME TO users');
  }

  /// Derives a username from an email address.
  ///
  /// Public for the migration test, which needs to assert the derivation
  /// separately from the table rebuild.
  static String usernameFromEmail(String? email) {
    final local = (email ?? '').split('@').first.toLowerCase();
    final cleaned = local.replaceAll(RegExp(r'[^a-z0-9._]'), '');
    final trimmed = cleaned.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
    // Falls back rather than failing: an address that sanitises down to
    // nothing usable must still end up with a working account.
    if (trimmed.length < 3) return 'owner';
    // Truncated with room for a dedup suffix, so appending one below cannot
    // push the result past what the account form itself accepts.
    return trimmed.length > 16 ? trimmed.substring(0, 16) : trimmed;
  }

  static String _uniqueUsername(String base, Set<String> taken) {
    if (!taken.contains(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base$i';
      if (!taken.contains(candidate)) return candidate;
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

  /// [table] exists so the v5 migration can build an identically shaped
  /// `users_new` before swapping it into place.
  ///
  /// `username` is stored already lowercased by `AuthController`, so a plain
  /// UNIQUE index is enough to stop two accounts differing only in case.
  static Future<void> _createUsers(Database db,
      {String table = 'users'}) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $table (
  id TEXT NOT NULL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
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
  -- Rented out rather than sold. `price` is then a rate per day, and the
  -- stock that goes out is expected back: see sale_lines.returned_qty.
  rental INTEGER NOT NULL DEFAULT 0,
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
  -- How long it was rented for. 1 for anything sold outright, so the line
  -- total is always qty * unit_price * days and nothing has to branch.
  days INTEGER NOT NULL DEFAULT 1,
  -- How many of `qty` have come back. Only ever above zero for a rental, and
  -- allowed to be less than `qty`: nineteen of twenty chairs is a real
  -- Sunday, and forcing it to be all-or-nothing would make the owner lie.
  returned_qty INTEGER NOT NULL DEFAULT 0,
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
