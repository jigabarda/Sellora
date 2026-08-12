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
    required this.email,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final DateTime createdAt;

  factory LocalUser.fromMap(Map<String, Object?> map) {
    return LocalUser(
      id: map['id']! as String,
      email: map['email']! as String,
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

  Future<void> login({required String email, required String password}) async {
    final normalized = email.trim().toLowerCase();
    final rows = await _db.query(
      'users',
      where: 'email = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw AuthException('No account found for that email.');
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
    required String email,
    required String password,
  }) async {
    if (password.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('@')) {
      throw AuthException('Enter a valid email.');
    }
    final existing = await _db.query(
      'users',
      where: 'email = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw AuthException('An account already exists for that email.');
    }

    final id = newLocalId('usr');
    final salt = _randomSalt();
    final hash = _hash(salt, password);

    await _db.transaction((txn) async {
      await txn.insert('users', {
        'id': id,
        'email': normalized,
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

  static String _randomSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String salt, String password) {
    return sha256.convert(utf8.encode('$salt$password')).toString();
  }
}
