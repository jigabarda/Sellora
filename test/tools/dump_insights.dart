import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/data/insights/insights_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Prints the insights the seeded database produces.
///
/// A generator, not a test — the filename omits `_test` so `flutter test` never
/// picks it up. Regenerate the database first, then:
///
///   flutter test test/tools/seed_device_db.dart
///   flutter test test/tools/dump_insights.dart
///
/// Useful for reading the actual sentences without installing to a device,
/// which is the only way to catch phrasing that is accurate but reads badly.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('dumps insights for the seeded business', () async {
    final path = '${Directory.current.path}/build/seed/sellora.db';
    if (!File(path).existsSync()) {
      fail('No seeded database. Run seed_device_db.dart first.');
    }

    final db = await databaseFactory.openDatabase(
      path,
      options: SelloraDatabase.openOptions(),
    );
    addTearDown(db.close);

    final insights = await InsightsService(db).generate('biz_seed');
    for (final insight in insights) {
      // ignore: avoid_print
      print(
          '[${insight.severity.name}] ${insight.title}\n    ${insight.detail}');
    }
    // ignore: avoid_print
    print('${insights.length} insight(s)');
  });
}
