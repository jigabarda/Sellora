import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/backup/backup_service.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does the backup actually carry everything?
///
/// The other backup tests check that the paths work. These check that nothing
/// is missing — a different question, and the one that only gets answered on
/// the worst day, when someone restores onto a replacement phone and finds out
/// what was left behind.
///
/// Two ways a backup goes quietly incomplete: a table added to the schema and
/// forgotten in the table list, or a column that the export or restore drops on
/// the way through. Both are silent — the file is valid, the restore succeeds,
/// and the data is simply not there.

const _bizId = 'biz_1';
const _userId = 'usr_1';

/// One row in every table, every column set to something recognisable.
///
/// Values are deliberately distinct per column, so a comparison after the round
/// trip cannot pass by two fields happening to hold the same thing.
Future<void> _seedEverything(Database db) async {
  await db.insert('users', {
    'id': _userId,
    'username': 'owner',
    'name': 'Test Owner',
    'salt': 'salt-value',
    'password_hash': 'hash-value',
    'created_at': 1001,
  });
  await db.insert('businesses', {
    'id': _bizId,
    'user_id': _userId,
    // Non-ASCII on purpose: it rides through a JSON encode and a UTF-8 decode.
    'name': 'Aling Rosa’s Tubig — Sampaloñ',
    'type': 'Water Station',
    'address': '12 Sampaloc St',
    'phone': '0917 000 1111',
    'created_at': 1002,
  });
  await db.insert('categories', {
    'id': 'cat_1',
    'business_id': _bizId,
    'name': 'Drinks',
    'created_at': 1003,
  });
  await db.insert('products', {
    'id': 'prd_1',
    'business_id': _bizId,
    'category_id': 'cat_1',
    'name': 'Chair',
    'description': 'Monobloc, white',
    'sku': 'CH-1',
    'unit': 'pcs',
    'price': 10.5,
    'stock': 50,
    'track_stock': 1,
    'rental': 1,
    'active': 1,
    'created_at': 1004,
  });
  await db.insert('customers', {
    'id': 'cus_1',
    'business_id': _bizId,
    'name': 'Mang Tonyo',
    'phone': '0918 222 3333',
    'email': 'tonyo@example.com',
    'notes': 'Pays Fridays',
    'created_at': 1005,
  });
  await db.insert('sales', {
    'id': 'sale_1',
    'business_id': _bizId,
    'customer_id': 'cus_1',
    'total': 530.0,
    'discount': 100.0,
    'created_at': 1006,
  });
  await db.insert('sale_lines', {
    'id': 'ln_1',
    'sale_id': 'sale_1',
    'product_id': 'prd_1',
    'name': 'Chair',
    'qty': 20,
    'unit_price': 10.5,
    'days': 3,
    'returned_qty': 5,
    'starts_at': 1700000000,
  });
  await db.insert('stock_ledger', {
    'id': 'stk_1',
    'business_id': _bizId,
    'product_id': 'prd_1',
    'delta': -20,
    'reason': 'rental_out',
    'ref_id': 'sale_1',
    'note': 'weekend booking',
    'at': 1007,
  });
  await db.insert('expenses', {
    'id': 'exp_1',
    'business_id': _bizId,
    'amount': 250.0,
    'category': 'Delivery',
    'note': 'tricycle',
    'at': 1008,
  });
  await db.insert('refunds', {
    'id': 'ref_1',
    'business_id': _bizId,
    'sale_id': 'sale_1',
    'amount': 30.0,
    'note': 'one chair cracked',
    'restock': 1,
    'at': 1009,
  });
}

Future<Set<String>> _schemaTables(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
  );
  return rows.map((r) => r['name']! as String).toSet();
}

Future<List<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name']! as String).toList();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late BackupService service;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    service = BackupService(db);
    await _seedEverything(db);
  });

  tearDown(() async => db.close());

  test('every table in the schema is one the backup carries', () async {
    // The failure this catches is a table added in a later release and never
    // added to the list. Nothing breaks, no test goes red, and that data simply
    // stops being backed up until someone restores and notices it is gone.
    expect(await _schemaTables(db), backupTables.toSet());
  });

  test('every table arrives in the exported file with its row', () async {
    final summary = await service.inspect(await service.exportToJson(_userId));

    for (final table in backupTables) {
      expect(
        summary.counts[table],
        1,
        reason: '$table was seeded with one row but the export has '
            '${summary.counts[table]}',
      );
    }
  });

  test('every column of every table survives the round trip', () async {
    // Column-level rather than row-count-level on purpose: an export that
    // dropped `days` or `discount` would still produce the right number of
    // rows, and the money would just be wrong on the new phone.
    final before = <String, Map<String, Object?>>{};
    for (final table in backupTables) {
      before[table] = (await db.query(table)).single;
    }

    final backup = await service.exportToJson(_userId);

    // Everything goes, the account included — exactly what a new phone is.
    await db.execute('PRAGMA foreign_keys = OFF');
    for (final table in backupTables) {
      await db.delete(table);
    }
    await db.execute('PRAGMA foreign_keys = ON');

    await service.restore(backup);

    for (final table in backupTables) {
      final rows = await db.query(table);
      expect(rows, hasLength(1), reason: '$table did not come back');

      final restored = rows.single;
      for (final column in await _columnsOf(db, table)) {
        expect(
          restored[column],
          before[table]![column],
          reason: '$table.$column changed across the round trip',
        );
      }
    }
  });

  test('a business cannot exist without an owner to back it up', () async {
    // The export finds businesses by `user_id`, so anything unowned would be
    // invisible to every backup on the device — present in the database and
    // absent from every file. The schema is what rules that out, and it is
    // worth pinning: relaxing this column later would silently open the hole.
    await expectLater(
      db.insert('businesses', {
        'id': 'biz_orphan',
        'user_id': null,
        'name': 'Unowned',
        'type': 'Retail Store',
        'address': '',
        'phone': '',
        'created_at': 1010,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('another account’s records stay out of this one’s backup', () async {
    await db.insert('users', {
      'id': 'usr_2',
      'username': 'other',
      'name': 'Someone Else',
      'salt': 's',
      'password_hash': 'h',
      'created_at': 1011,
    });
    await db.insert('businesses', {
      'id': 'biz_2',
      'user_id': 'usr_2',
      'name': 'Their Shop',
      'type': 'Retail Store',
      'address': '',
      'phone': '',
      'created_at': 1012,
    });
    await db.insert('expenses', {
      'id': 'exp_2',
      'business_id': 'biz_2',
      'amount': 99.0,
      'category': 'Rent',
      'note': '',
      'at': 1013,
    });

    final summary = await service.inspect(await service.exportToJson(_userId));
    expect(summary.businesses, 1);
    expect(summary.counts['expenses'], 1, reason: 'not their expense too');
    expect(summary.counts['users'], 1, reason: 'one account per file');
  });
}
