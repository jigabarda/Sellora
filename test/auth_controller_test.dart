import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/auth/auth_controller.dart';
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
