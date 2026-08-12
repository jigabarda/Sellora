import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Marker written into every backup file so we can reject foreign JSON.
const _formatTag = 'sellora-backup';

/// Bumped when the backup envelope itself changes shape.
const backupFormatVersion = 1;

/// Must track `SelloraDatabase._version`. A backup taken on a newer schema
/// cannot be restored into an older build.
const backupSchemaVersion = 4;

/// Parent-before-child. Restore inserts in this order so foreign keys hold.
const _insertOrder = <String>[
  'users',
  'businesses',
  'categories',
  'products',
  'customers',
  'sales',
  'sale_lines',
  'stock_ledger',
  'expenses',
  'refunds',
];

/// Child-before-parent. `sale_lines` must go before `products` because
/// `sale_lines.product_id` is ON DELETE RESTRICT, not CASCADE.
const _deleteOrder = <String>[
  'sale_lines',
  'stock_ledger',
  'refunds',
  'sales',
  'expenses',
  'customers',
  'products',
  'categories',
  'businesses',
];

/// Tables scoped directly by `business_id`.
const _businessScoped = <String>{
  'categories',
  'products',
  'customers',
  'sales',
  'stock_ledger',
  'expenses',
  'refunds',
};

class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Row counts for a backup, used to preview a file before restoring it.
class BackupSummary {
  const BackupSummary({
    required this.userId,
    required this.username,
    required this.exportedAt,
    required this.counts,
  });

  final String userId;
  final String username;
  final DateTime exportedAt;
  final Map<String, int> counts;

  int get businesses => counts['businesses'] ?? 0;
  int get products => counts['products'] ?? 0;
  int get sales => counts['sales'] ?? 0;
  int get customers => counts['customers'] ?? 0;

  int get totalRows => counts.values.fold(0, (a, b) => a + b);
}

/// Exports/restores one local account's data as a plain JSON file.
///
/// Everything stays on-device. The file leaves the app only through the
/// system share sheet, where the user picks the destination themselves.
class BackupService {
  BackupService(this._db);

  final Database _db;

  /// Serializes [userId]'s account and all of its businesses to JSON.
  Future<String> exportToJson(String userId) async {
    final userRows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (userRows.isEmpty) {
      throw BackupException('No local account is signed in.');
    }

    final businessRows = await _db.query(
      'businesses',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final businessIds =
        businessRows.map((r) => r['id']! as String).toList(growable: false);

    final tables = <String, List<Map<String, Object?>>>{
      'users': userRows,
      'businesses': businessRows,
    };

    if (businessIds.isEmpty) {
      for (final t in _insertOrder) {
        tables.putIfAbsent(t, () => const []);
      }
    } else {
      final placeholders = List.filled(businessIds.length, '?').join(', ');
      for (final table in _businessScoped) {
        tables[table] = await _db.query(
          table,
          where: 'business_id IN ($placeholders)',
          whereArgs: businessIds,
        );
      }
      // Join instead of an IN over sale ids — sale counts are unbounded and
      // would blow past SQLite's variable limit on a busy store.
      tables['sale_lines'] = await _db.rawQuery(
        '''
SELECT sl.* FROM sale_lines sl
INNER JOIN sales s ON s.id = sl.sale_id
WHERE s.business_id IN ($placeholders)
''',
        businessIds,
      );
    }

    final envelope = <String, Object?>{
      'format': _formatTag,
      'formatVersion': backupFormatVersion,
      'schemaVersion': backupSchemaVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'userId': userId,
      'tables': {
        for (final t in _insertOrder)
          t: tables[t] ?? const <Map<String, Object?>>[],
      },
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Writes the backup to the cache directory and returns the file.
  ///
  /// Cache is deliberate: the copy is a hand-off for the share sheet, not
  /// storage. The user's chosen destination is the real backup.
  Future<File> writeBackupFile(String userId, DateTime stamp) async {
    final json = await exportToJson(userId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${backupFileName(stamp)}');
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// Parses and validates a backup file without writing anything.
  Future<BackupSummary> inspect(String rawJson) async {
    final envelope = _decode(rawJson);
    final tables = _tablesOf(envelope);

    final users = tables['users'] ?? const [];
    if (users.isEmpty) {
      throw BackupException('Backup does not contain an account record.');
    }

    return BackupSummary(
      userId: users.first['id']! as String,
      username: (users.first['username'] as String?) ?? '',
      exportedAt: DateTime.fromMillisecondsSinceEpoch(
        (envelope['exportedAt'] as num?)?.toInt() ?? 0,
      ),
      counts: {
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
    );
  }

  /// Wipes the backup account's existing local data and loads the file in its
  /// place. Returns the restored user id.
  ///
  /// All-or-nothing: any failure rolls the whole transaction back and the
  /// current data survives untouched.
  Future<String> restore(String rawJson) async {
    final envelope = _decode(rawJson);
    final tables = _tablesOf(envelope);

    final users = tables['users'] ?? const [];
    if (users.isEmpty) {
      throw BackupException('Backup does not contain an account record.');
    }
    final restoredUserId = users.first['id']! as String;
    final restoredUsername = (users.first['username'] as String?) ?? '';

    // A different local account already holding this username would violate
    // the UNIQUE constraint halfway through the restore. Fail early with a
    // message the user can act on instead of a raw SQLite error.
    final usernameClash = await _db.query(
      'users',
      where: 'username = ? AND id != ?',
      whereArgs: [restoredUsername, restoredUserId],
      limit: 1,
    );
    if (usernameClash.isNotEmpty) {
      throw BackupException(
        'A different local account already uses @$restoredUsername. '
        'Sign in to that account and restore from there, or clear app data first.',
      );
    }

    await _db.transaction((txn) async {
      final existing = await txn.query(
        'businesses',
        columns: ['id'],
        where: 'user_id = ?',
        whereArgs: [restoredUserId],
      );
      final ids =
          existing.map((r) => r['id']! as String).toList(growable: false);

      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(', ');
        for (final table in _deleteOrder) {
          switch (table) {
            case 'sale_lines':
              await txn.rawDelete(
                'DELETE FROM sale_lines WHERE sale_id IN '
                '(SELECT id FROM sales WHERE business_id IN ($placeholders))',
                ids,
              );
            case 'businesses':
              await txn.delete('businesses',
                  where: 'user_id = ?', whereArgs: [restoredUserId]);
            default:
              await txn.delete(
                table,
                where: 'business_id IN ($placeholders)',
                whereArgs: ids,
              );
          }
        }
      }

      for (final table in _insertOrder) {
        final rows = tables[table] ?? const [];
        for (final row in rows) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: table == 'users'
                ? ConflictAlgorithm.replace
                : ConflictAlgorithm.abort,
          );
        }
      }
    });

    return restoredUserId;
  }

  Map<String, Object?> _decode(String rawJson) {
    final Object? parsed;
    try {
      parsed = jsonDecode(rawJson);
    } on FormatException {
      throw BackupException('That file is not valid JSON.');
    }

    if (parsed is! Map<String, Object?>) {
      throw BackupException('That file is not a Sellora backup.');
    }
    if (parsed['format'] != _formatTag) {
      throw BackupException('That file is not a Sellora backup.');
    }

    final formatVersion = (parsed['formatVersion'] as num?)?.toInt() ?? 0;
    if (formatVersion > backupFormatVersion) {
      throw BackupException(
        'This backup was made by a newer version of Sellora. Update the app first.',
      );
    }

    final schemaVersion = (parsed['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion > backupSchemaVersion) {
      throw BackupException(
        'This backup uses database v$schemaVersion but this build only supports '
        'v$backupSchemaVersion. Update the app first.',
      );
    }

    return parsed;
  }

  Map<String, List<Map<String, Object?>>> _tablesOf(
      Map<String, Object?> envelope) {
    final raw = envelope['tables'];
    if (raw is! Map) {
      throw BackupException('Backup file is missing its data section.');
    }

    final out = <String, List<Map<String, Object?>>>{};
    for (final table in _insertOrder) {
      final rows = raw[table];
      if (rows == null) {
        out[table] = const [];
        continue;
      }
      if (rows is! List) {
        throw BackupException('Backup section "$table" is malformed.');
      }
      out[table] = rows.map((r) {
        if (r is! Map) {
          throw BackupException('Backup section "$table" contains a bad row.');
        }
        return Map<String, Object?>.from(r);
      }).toList(growable: false);
    }
    return out;
  }
}

String backupFileName(DateTime stamp) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'sellora-backup-${stamp.year}-${two(stamp.month)}-${two(stamp.day)}'
      '-${two(stamp.hour)}${two(stamp.minute)}.json';
}
