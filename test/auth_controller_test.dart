import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/auth/auth_controller.dart';
import 'package:sellora_mobile/data/backup/backup_service.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late AuthController auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );
    auth = AuthController(db, await SharedPreferences.getInstance());
    await auth.register(
      name: 'Test Owner',
      username: '  Owner  ',
      password: 'secret123',
    );
  });

  tearDown(() async => db.close());

  group('recovering an account from a backup', () {
    test('a restored account can be signed into on a phone that has none',
        () async {
      // The whole scenario: the old phone is gone, this one has never seen
      // the account, and the only thing left is the file.
      final backup = await BackupService(db).exportToJson(auth.state.userId!);
      await auth.logout();
      await db.delete('users');
      expect(await db.query('users'), isEmpty, reason: 'a fresh phone');

      final restoredId = await BackupService(db).restore(backup);
      await auth.adoptRestoredSession(restoredId);

      expect(auth.isLoggedIn, isTrue);
      expect((await auth.currentUser())!.username, 'owner');
    });

    test('the password from the old phone still works after restoring',
        () async {
      // The account travels inside the file, salt and hash included, so the
      // password someone has been typing for a year keeps working. Losing the
      // phone must not mean losing the credentials with it.
      final backup = await BackupService(db).exportToJson(auth.state.userId!);
      await auth.logout();
      await db.delete('users');

      await BackupService(db).restore(backup);
      await auth.login(username: 'owner', password: 'secret123');

      expect(auth.isLoggedIn, isTrue);
    });

    test('adopting a session for an account that is not there is refused',
        () async {
      // Otherwise the app would sit signed in as nobody, which every screen
      // downstream reads as "logged in" and then fails to find anything.
      await expectLater(
        auth.adoptRestoredSession('usr_does_not_exist'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.state.userId, isNot('usr_does_not_exist'));
    });

    test('a forgotten password can be replaced after restoring', () async {
      // The whole recovery story end to end: password forgotten, backup file
      // in hand, and a way back in that does not need the old one.
      final backup = await BackupService(db).exportToJson(auth.state.userId!);
      await auth.logout();
      await db.delete('users');

      final id = await BackupService(db).restore(backup);
      await auth.adoptRestoredSession(id);
      await auth.setPasswordAfterRestore('brandnew456');

      await auth.logout();
      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });

    test('the forgotten password stops working once it is replaced', () async {
      await auth.setPasswordAfterRestore('brandnew456');
      await auth.logout();

      await expectLater(
        auth.login(username: 'owner', password: 'secret123'),
        throwsA(isA<AuthException>()),
      );
    });

    test('replacing the password rotates the salt too', () async {
      Future<String> saltNow() async => (await db.query('users',
              columns: ['salt'],
              where: 'id = ?',
              whereArgs: [auth.state.userId]))
          .single['salt']! as String;

      final before = await saltNow();
      await auth.setPasswordAfterRestore('brandnew456');

      // A reused salt would leave the old hash meaningful against a rainbow
      // table built for it, which is the point of having one at all.
      expect(await saltNow(), isNot(before));
    });

    test('a replacement password is held to the same minimum', () async {
      await expectLater(
        auth.setPasswordAfterRestore('short'),
        throwsA(isA<AuthException>()),
      );
      // And the old one still works, so a rejected attempt locks nobody out.
      await auth.logout();
      await auth.login(username: 'owner', password: 'secret123');
      expect(auth.isLoggedIn, isTrue);
    });

    test('nobody signed in can set a password', () async {
      await auth.logout();
      await expectLater(
        auth.setPasswordAfterRestore('brandnew456'),
        throwsA(isA<AuthException>()),
      );
    });

    test('the adopted session survives a restart', () async {
      final id = auth.state.userId!;
      await auth.logout();
      await auth.adoptRestoredSession(id);

      // A second controller over the same prefs is what a relaunch looks like.
      final relaunched =
          AuthController(db, await SharedPreferences.getInstance());
      await relaunched.restoreSession();

      expect(relaunched.state.userId, id);
    });
  });

  group('password stretching', () {
    /// Writes a credential in the pre-stretching format: sha256(salt+secret).
    /// This is what every account made before this change actually holds, and
    /// the only honest way to test that they keep working.
    Future<void> writeLegacyPassword(String password) async {
      const salt = 'legacy-salt';
      final digest = sha256.convert(utf8.encode('$salt$password')).toString();
      await db.update(
        'users',
        {'salt': salt, 'password_hash': digest},
        where: 'id = ?',
        whereArgs: [auth.state.userId],
      );
    }

    Future<Map<String, Object?>> userRow() async =>
        (await db.query('users', where: 'username = ?', whereArgs: ['owner']))
            .single;

    test('a new account is stored stretched, not as a bare digest', () async {
      final stored = (await userRow())['password_hash']! as String;

      expect(stored, startsWith('pbkdf2\$'));
      expect(
        stored,
        isNot(sha256
            .convert(utf8.encode('${(await userRow())['salt']}secret123'))
            .toString()),
        reason: 'a bare sha256 digest would mean nothing changed',
      );
    });

    test('an account made before stretching can still sign in', () async {
      // The one thing that must not break. Locking people out of their own
      // records to improve a hash would be worse than the weak hash.
      await writeLegacyPassword('secret123');
      await auth.logout();

      await auth.login(username: 'owner', password: 'secret123');
      expect(auth.isLoggedIn, isTrue);
    });

    test('signing in upgrades an old credential in passing', () async {
      await writeLegacyPassword('secret123');
      await auth.logout();
      expect((await userRow())['password_hash'], isNot(startsWith('pbkdf2\$')));

      await auth.login(username: 'owner', password: 'secret123');

      final after = await userRow();
      expect(after['password_hash'], startsWith('pbkdf2\$'));
      expect(after['salt'], isNot('legacy-salt'),
          reason: 'a rehash gets a fresh salt, like every other write');

      // And the same password keeps working against the upgraded row.
      await auth.logout();
      await auth.login(username: 'owner', password: 'secret123');
      expect(auth.isLoggedIn, isTrue);
    });

    test('a wrong password against an old credential is still refused',
        () async {
      await writeLegacyPassword('secret123');
      await auth.logout();

      await expectLater(
        auth.login(username: 'owner', password: 'wrongpassword'),
        throwsA(isA<AuthException>()),
      );
      // And a failed attempt does not quietly rewrite the row.
      expect((await userRow())['password_hash'], isNot(startsWith('pbkdf2\$')));
    });

    test('the stored value carries its own work factor', () async {
      // So the count can be raised later without stranding today's rows.
      final stored = (await userRow())['password_hash']! as String;
      final parts = stored.split('\$');

      expect(parts, hasLength(3));
      expect(int.parse(parts[1]), greaterThanOrEqualTo(100000));
      expect(parts[2], hasLength(64), reason: '32 bytes as hex');
    });

    test('the same password under a different salt gives a different hash',
        () async {
      await auth.register(
        name: 'Second',
        username: 'second',
        password: 'secret123',
      );

      final rows = await db.query('users', orderBy: 'created_at ASC');
      final first = rows.firstWhere((r) => r['username'] == 'owner');
      final second = rows.firstWhere((r) => r['username'] == 'second');

      expect(first['salt'], isNot(second['salt']));
      expect(first['password_hash'], isNot(second['password_hash']),
          reason: 'identical passwords must not collide across accounts');
    });

    test('changing a password writes the stretched format', () async {
      await auth.changePassword(
        currentPassword: 'secret123',
        newPassword: 'brandnew456',
      );

      expect((await userRow())['password_hash'], startsWith('pbkdf2\$'));
      await auth.logout();
      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });

    test('a recovery code is stretched too', () async {
      final code = await auth.createRecoveryCode(password: 'secret123');
      final stored = (await userRow())['recovery_hash']! as String;

      expect(stored, startsWith('pbkdf2\$'));
      // And still verifies, which is what the format change could have broken.
      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: code,
        newPassword: 'brandnew456',
      );
      await auth.logout();
      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });
  });

  group('recovery codes', () {
    test('a code resets the password without touching anything else', () async {
      // The case the whole feature exists for: no backup file, no memory of
      // the password, and a code written on the back of a receipt.
      final code = await auth.createRecoveryCode(password: 'secret123');
      await auth.logout();

      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: code,
        newPassword: 'brandnew456',
      );

      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });

    test('the code is accepted however it was written down', () async {
      // Shown as ABCD-EFGH-JKMN and typed back months later as
      // "abcdefghjkmn", or with stray spaces. Hashing the dashed form would
      // have made every real attempt fail.
      final code = await auth.createRecoveryCode(password: 'secret123');
      final messy = ' ${code.replaceAll('-', '').toLowerCase()} ';

      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: messy,
        newPassword: 'brandnew456',
      );

      await auth.logout();
      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });

    test('the records are untouched by a reset', () async {
      // Stated as a test because it is the promise being made: forgetting a
      // password must never cost anybody their sales.
      await db.insert('businesses', {
        'id': 'biz_1',
        'user_id': auth.state.userId,
        'name': 'Sari-sari',
        'type': 'Retail Store',
        'address': '',
        'phone': '',
        'created_at': 1,
      });

      final code = await auth.createRecoveryCode(password: 'secret123');
      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: code,
        newPassword: 'brandnew456',
      );

      expect(await db.query('businesses'), hasLength(1));
    });

    test('a spent code cannot be used twice', () async {
      // Otherwise a slip of paper becomes a permanent second key: anyone who
      // ever glimpsed it could take the account back at any time.
      final code = await auth.createRecoveryCode(password: 'secret123');
      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: code,
        newPassword: 'brandnew456',
      );

      await expectLater(
        auth.resetPasswordWithRecoveryCode(
          username: 'owner',
          code: code,
          newPassword: 'thirdpassword',
        ),
        throwsA(isA<AuthException>()),
      );
      // And the password from the successful reset still stands.
      await auth.logout();
      await auth.login(username: 'owner', password: 'brandnew456');
      expect(auth.isLoggedIn, isTrue);
    });

    test('a reset hands back a replacement code that works', () async {
      // Spending the only code must not leave the owner with no way back the
      // next time, so the reset issues its successor.
      final first = await auth.createRecoveryCode(password: 'secret123');
      final second = await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: first,
        newPassword: 'brandnew456',
      );

      expect(second, isNot(first));
      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: second,
        newPassword: 'thirdpass789',
      );
      await auth.logout();
      await auth.login(username: 'owner', password: 'thirdpass789');
      expect(auth.isLoggedIn, isTrue);
    });

    test('a wrong code changes nothing', () async {
      await auth.createRecoveryCode(password: 'secret123');

      await expectLater(
        auth.resetPasswordWithRecoveryCode(
          username: 'owner',
          code: 'ZZZZ-ZZZZ-ZZZZ',
          newPassword: 'brandnew456',
        ),
        throwsA(isA<AuthException>()),
      );
      await auth.logout();
      await auth.login(username: 'owner', password: 'secret123');
      expect(auth.isLoggedIn, isTrue);
    });

    test('an account with no code says so rather than failing vaguely',
        () async {
      // Every account predating this feature is in exactly this state, so the
      // message has to point somewhere useful.
      await expectLater(
        auth.resetPasswordWithRecoveryCode(
          username: 'owner',
          code: 'ZZZZ-ZZZZ-ZZZZ',
          newPassword: 'brandnew456',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('no recovery code'),
        )),
      );
    });

    test('making a code needs the current password', () async {
      // Otherwise anyone holding an unlocked phone could walk off with a key
      // to it and lock the owner out later.
      await expectLater(
        auth.createRecoveryCode(password: 'wrongpassword'),
        throwsA(isA<AuthException>()),
      );
      expect(await auth.hasRecoveryCode('owner'), isFalse);
    });

    test('making a new code retires the old one', () async {
      final first = await auth.createRecoveryCode(password: 'secret123');
      await auth.createRecoveryCode(password: 'secret123');

      await expectLater(
        auth.resetPasswordWithRecoveryCode(
          username: 'owner',
          code: first,
          newPassword: 'brandnew456',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('hasRecoveryCode reports what the account actually has', () async {
      expect(await auth.hasRecoveryCode('owner'), isFalse);
      await auth.createRecoveryCode(password: 'secret123');
      expect(await auth.hasRecoveryCode('  OWNER '), isTrue,
          reason: 'the username is normalised like everywhere else');
      expect(await auth.hasRecoveryCode('nobody'), isFalse);
    });

    test('the code is never readable back out of the database', () async {
      final code = await auth.createRecoveryCode(password: 'secret123');
      final row = (await db.query('users')).single;

      // Only a hash is kept. If this ever fails, the code is being stored in
      // the clear and anyone with the database file has the account.
      expect(row.values.map((v) => '$v').join(' '),
          isNot(contains(AuthController.normalizeRecoveryCode(code))));
    });

    test('a reset is refused for a password below the minimum', () async {
      final code = await auth.createRecoveryCode(password: 'secret123');
      await expectLater(
        auth.resetPasswordWithRecoveryCode(
          username: 'owner',
          code: code,
          newPassword: 'short',
        ),
        throwsA(isA<AuthException>()),
      );
      // The code is unspent, so a typo does not cost the one way back in.
      await auth.resetPasswordWithRecoveryCode(
        username: 'owner',
        code: code,
        newPassword: 'longenough1',
      );
      await auth.logout();
      await auth.login(username: 'owner', password: 'longenough1');
      expect(auth.isLoggedIn, isTrue);
    });
  });

  test('currentUser returns the signed-in account without credential fields',
      () async {
    final user = await auth.currentUser();

    expect(user, isNotNull);
    expect(user!.username, 'owner');
    expect(user.name, 'Test Owner');
    expect(user.id, auth.state.userId);
  });

  test('currentUser is null once signed out', () async {
    await auth.logout();
    expect(await auth.currentUser(), isNull);
  });

  test('updateName trims and persists', () async {
    await auth.updateName('  Juan Dela Cruz  ');
    expect((await auth.currentUser())!.name, 'Juan Dela Cruz');
  });

  test('updateName rejects an empty name', () async {
    await expectLater(auth.updateName('   '), throwsA(isA<AuthException>()));
    expect((await auth.currentUser())!.name, 'Test Owner');
  });

  test('changePassword swaps the credential and the old one stops working',
      () async {
    await auth.changePassword(
      currentPassword: 'secret123',
      newPassword: 'brandnew456',
    );

    await auth.logout();
    await expectLater(
      auth.login(username: 'owner', password: 'secret123'),
      throwsA(isA<AuthException>()),
    );
    await auth.login(username: 'owner', password: 'brandnew456');
    expect(auth.isLoggedIn, isTrue);
  });

  test('changePassword rotates the salt, not just the hash', () async {
    Future<Map<String, Object?>> row() async => (await db
            .query('users', where: 'id = ?', whereArgs: [auth.state.userId]))
        .single;

    final before = await row();
    await auth.changePassword(
      currentPassword: 'secret123',
      newPassword: 'brandnew456',
    );
    final after = await row();

    expect(after['salt'], isNot(before['salt']));
    expect(after['password_hash'], isNot(before['password_hash']));
  });

  test('changePassword refuses a wrong current password', () async {
    await expectLater(
      auth.changePassword(currentPassword: 'wrong', newPassword: 'brandnew456'),
      throwsA(isA<AuthException>()),
    );

    // The original credential must still work after a failed attempt.
    await auth.logout();
    await auth.login(username: 'owner', password: 'secret123');
    expect(auth.isLoggedIn, isTrue);
  });

  test('changePassword enforces the minimum length', () async {
    await expectLater(
      auth.changePassword(currentPassword: 'secret123', newPassword: 'short'),
      throwsA(isA<AuthException>()),
    );
  });

  test('profile edits require a session', () async {
    await auth.logout();
    await expectLater(auth.updateName('Nobody'), throwsA(isA<AuthException>()));
    await expectLater(
      auth.changePassword(
          currentPassword: 'secret123', newPassword: 'brandnew456'),
      throwsA(isA<AuthException>()),
    );
  });
}
