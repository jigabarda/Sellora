import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../util/ids.dart';

const _prefActiveUserId = 'active_user_id';

class AuthState {
  const AuthState({this.userId});
  final String? userId;
}

/// The signed-in local account. Deliberately excludes `salt`/`password_hash`
/// so credential material never reaches the widget tree.
class LocalUser {
  const LocalUser({
    required this.id,
    required this.username,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String name;
  final DateTime createdAt;

  factory LocalUser.fromMap(Map<String, Object?> map) {
    return LocalUser(
      id: map['id']! as String,
      username: map['username']! as String,
      name: map['name']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
    );
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Local session + salted SHA-256 password (offline demo; upgrade for production hardening).
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._db, this._prefs) : super(const AuthState(userId: null));

  final Database _db;
  final SharedPreferences _prefs;

  bool get isLoggedIn => state.userId != null;

  Future<void> restoreSession() async {
    final id = _prefs.getString(_prefActiveUserId);
    if (id == null) {
      state = const AuthState(userId: null);
      return;
    }
    final rows =
        await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      await _prefs.remove(_prefActiveUserId);
      state = const AuthState(userId: null);
    } else {
      state = AuthState(userId: id);
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final normalized = normalizeUsername(username);
    final rows = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AuthException('No account found for that username.');
    }
    final row = rows.first;
    final id = row['id']! as String;
    final salt = row['salt']! as String;
    final stored = row['password_hash']! as String;
    final hash = _hash(salt, password);
    if (hash != stored) {
      throw AuthException('Incorrect password.');
    }
    await _prefs.setString(_prefActiveUserId, id);
    state = AuthState(userId: id);
  }

  Future<void> register({
    required String name,
    required String username,
    required String password,
  }) async {
    if (password.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    final normalized = normalizeUsername(username);
    final invalid = describeUsernameProblem(normalized);
    if (invalid != null) {
      throw AuthException(invalid);
    }
    final existing = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw AuthException('That username is already taken.');
    }

    final id = newLocalId('usr');
    final salt = _randomSalt();
    final hash = _hash(salt, password);

    await _db.transaction((txn) async {
      await txn.insert('users', {
        'id': id,
        'username': normalized,
        'name': name.trim(),
        'salt': salt,
        'password_hash': hash,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await txn.rawUpdate(
        'UPDATE businesses SET user_id = ? WHERE user_id IS NULL',
        [id],
      );
    });

    await _prefs.setString(_prefActiveUserId, id);
    state = AuthState(userId: id);
  }

  /// Signs in the account a backup just restored, without asking for the
  /// password again.
  ///
  /// Safe because the file already grants everything a session would: a backup
  /// is plain JSON, so whoever can restore it can read every sale in it with a
  /// text editor. Demanding the password here would protect nothing and would
  /// strand the one person it is meant to help — someone whose phone is gone,
  /// holding the only copy of their own records.
  ///
  /// Throws if [userId] is not in the database, which would otherwise leave a
  /// session pointing at nobody.
  Future<void> adoptRestoredSession(String userId) async {
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AuthException('The restored account could not be found.');
    }
    await _prefs.setString(_prefActiveUserId, userId);
    state = AuthState(userId: userId);
  }

  /// Sets a new password without asking for the old one.
  ///
  /// The forgotten-password path, and the only one there can be: the hash is
  /// one-way and there is no server to mail a link from, so the password itself
  /// is unrecoverable by design. What can be re-established is *proof of
  /// ownership*, and a backup file is that proof — it is the account's own
  /// records, which nobody else has.
  ///
  /// Reachable only straight after a restore, because that is the moment the
  /// proof was shown. Exposing it from settings would let anyone who found an
  /// unlocked phone lock its owner out of it, which is a worse problem than the
  /// one this solves.
  Future<void> setPasswordAfterRestore(String newPassword) async {
    final id = state.userId;
    if (id == null) {
      throw AuthException('You are not signed in.');
    }
    if (newPassword.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    // Fresh salt, same as an ordinary change: the old hash must not survive.
    final salt = _randomSalt();
    await _db.update(
      'users',
      {'salt': salt, 'password_hash': _hash(salt, newPassword)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Makes a recovery code, replacing any previous one, and returns it in the
  /// clear so it can be shown once.
  ///
  /// Guarded by the current password for the same reason `changePassword` is:
  /// otherwise anyone who found an unlocked phone could take a code away with
  /// them and lock the owner out of it later.
  ///
  /// Only the hash is kept, salted separately from the password so the two
  /// secrets share nothing. Nobody can read the code back afterwards — not the
  /// owner, and not this app.
  Future<String> createRecoveryCode({required String password}) async {
    final id = state.userId;
    if (id == null) {
      throw AuthException('You are not signed in.');
    }
    final rows =
        await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw AuthException('Your account could not be found.');
    }
    final row = rows.first;
    if (_hash(row['salt']! as String, password) !=
        row['password_hash']! as String) {
      throw AuthException('Incorrect password.');
    }

    return _issueRecoveryCode(id);
  }

  /// Sets a new password for [username] on the strength of a recovery code,
  /// and hands back a fresh code to replace the one just spent.
  ///
  /// No session required — the whole point is that the owner cannot get one.
  /// The code is single use: leaving it live would turn a slip of paper into a
  /// permanent second key to the account, so it is replaced here and the new
  /// one is returned to be written down in its place.
  ///
  /// Nothing but the credential changes. Not one sale, product or business is
  /// touched — a forgotten password is not a reason to lose the records.
  Future<String> resetPasswordWithRecoveryCode({
    required String username,
    required String code,
    required String newPassword,
  }) async {
    if (newPassword.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }

    final rows = await _db.query(
      'users',
      where: 'username = ?',
      whereArgs: [normalizeUsername(username)],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AuthException('No account found for that username.');
    }
    final row = rows.first;
    final recoverySalt = row['recovery_salt'] as String?;
    final recoveryHash = row['recovery_hash'] as String?;
    if (recoverySalt == null || recoveryHash == null) {
      throw AuthException(
        'That account has no recovery code. Restore a backup file instead.',
      );
    }
    if (_hash(recoverySalt, normalizeRecoveryCode(code)) != recoveryHash) {
      throw AuthException('That recovery code does not match.');
    }

    final id = row['id']! as String;
    final salt = _randomSalt();
    await _db.update(
      'users',
      {'salt': salt, 'password_hash': _hash(salt, newPassword)},
      where: 'id = ?',
      whereArgs: [id],
    );
    return _issueRecoveryCode(id);
  }

  /// Whether [username] has a recovery code, so a screen can say which way out
  /// exists before asking for something the account cannot check.
  Future<bool> hasRecoveryCode(String username) async {
    final rows = await _db.query(
      'users',
      columns: ['recovery_hash'],
      where: 'username = ?',
      whereArgs: [normalizeUsername(username)],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['recovery_hash'] != null;
  }

  Future<String> _issueRecoveryCode(String userId) async {
    final code = _randomRecoveryCode();
    final salt = _randomSalt();
    await _db.update(
      'users',
      {
        'recovery_salt': salt,
        // Hashed in its normalised form, which is what verification will
        // compare against. Hashing the dashed version instead would make every
        // code fail, since nobody types the dashes back identically.
        'recovery_hash': _hash(salt, normalizeRecoveryCode(code)),
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    return code;
  }

  /// Twelve characters in three groups, from an alphabet with no 0/O, 1/I/L or
  /// 5/S in it. Someone is going to copy this off a screen onto the back of a
  /// receipt and type it in months later, and the commonest way that fails is
  /// two characters that look alike.
  static String _randomRecoveryCode() {
    const alphabet = '23456789ABCDEFGHJKMNPQRTUVWXYZ';
    final random = Random.secure();
    final chars = List<String>.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    );
    return '${chars.sublist(0, 4).join()}-'
        '${chars.sublist(4, 8).join()}-'
        '${chars.sublist(8).join()}';
  }

  /// Dashes, spaces and case are how it is written down, not what it is.
  static String normalizeRecoveryCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  Future<void> logout() async {
    await _prefs.remove(_prefActiveUserId);
    state = const AuthState(userId: null);
  }

  /// Reads the signed-in account, or null when nobody is signed in.
  Future<LocalUser?> currentUser() async {
    final id = state.userId;
    if (id == null) return null;
    final rows =
        await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LocalUser.fromMap(rows.first);
  }

  Future<void> updateName(String name) async {
    final id = state.userId;
    if (id == null) {
      throw AuthException('You are not signed in.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw AuthException('Enter your name.');
    }
    final updated = await _db.update(
      'users',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated != 1) {
      throw AuthException('Your account could not be found.');
    }
  }

  /// The web app changes passwords through an authenticated Supabase session.
  /// There is no session to lean on locally and the device may be shared, so
  /// the current password is required here.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final id = state.userId;
    if (id == null) {
      throw AuthException('You are not signed in.');
    }
    if (newPassword.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    final rows =
        await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw AuthException('Your account could not be found.');
    }
    final row = rows.first;
    if (_hash(row['salt']! as String, currentPassword) !=
        row['password_hash']! as String) {
      throw AuthException('Current password is incorrect.');
    }

    // Fresh salt on every change so an old hash never survives a rotation.
    final salt = _randomSalt();
    await _db.update(
      'users',
      {'salt': salt, 'password_hash': _hash(salt, newPassword)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Trims and lowercases so "  James " and "james" are the same account.
  ///
  /// Every read and write of `username` goes through this, which is what lets
  /// the column get away with a plain UNIQUE index instead of a case-insensitive
  /// one.
  static String normalizeUsername(String raw) => raw.trim().toLowerCase();

  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._]*$');

  /// Returns why [username] is unacceptable, or null when it is fine.
  ///
  /// Shared with the sign-up form so the field can show the same rule the
  /// controller enforces, rather than the two drifting apart. Expects an
  /// already-normalised value.
  static String? describeUsernameProblem(String username) {
    if (username.length < 3) {
      return 'Username must be at least 3 characters.';
    }
    if (username.length > 20) {
      return 'Username must be 20 characters or fewer.';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'Use letters, numbers, dots and underscores, starting with a letter or number.';
    }
    return null;
  }

  static String _randomSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt$password')).toString();
  }
}
