import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Not a test — an inspector, parked in `test/` for the same reason as the
/// other tools here: it is the only place the toolchain runs Dart with the
/// project's dependencies available.
///
/// Prints the most recent sales from a database pulled off a device, so a
/// device run can be checked against what the UI claimed. Point it at the file
/// with `--dart-define=db=<path>`:
///
///   flutter test test/tools/inspect_device_db.dart --dart-define=db=C:\path\to\sellora.db
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('prints recent sales', () async {
    const path = String.fromEnvironment('db');
    if (path.isEmpty || !File(path).existsSync()) {
      stdout.writeln('no database at "$path"');
      return;
    }

    final db = await databaseFactory.openDatabase(path);

    final count = await db.rawQuery('SELECT COUNT(*) c FROM sales');
    stdout.writeln('total sales: ${count.first['c']}');

    final rows = await db.rawQuery('''
SELECT s.id, s.total, s.customer_id, s.created_at,
       (SELECT GROUP_CONCAT(l.qty || ' x ' || l.name, ' | ')
          FROM sale_lines l WHERE l.sale_id = s.id) AS lines
FROM sales s ORDER BY s.created_at DESC LIMIT 12
''');

    stdout.writeln('--- 12 most recent ---');
    for (final r in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int);
      stdout.writeln('${at.toIso8601String()}  ${r['id']}  '
          'PHP ${r['total']}  cust=${r['customer_id']}  ${r['lines']}');
    }

    await db.close();
  });
}
