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
