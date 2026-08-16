import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sellora_mobile/app.dart';
import 'package:sellora_mobile/core/brand_palette.dart';
import 'package:sellora_mobile/core/theme_controller.dart';
import 'package:sellora_mobile/data/auth/auth_controller.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:sellora_mobile/providers.dart';
import 'package:sellora_mobile/router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A running app backed by an in-memory database, for widget smoke tests.
class AppHarness {
  AppHarness._(this.db, this.container, this.businessId);

  final Database db;
  final ProviderContainer container;

  /// The seeded business every business-scoped route is opened against.
  final String businessId;

  GoRouter get router => container.read(goRouterProvider);

  Future<void> dispose() async {
    container.dispose();
    // Closing is real I/O; a fake-async await here would hang the teardown.
    unawaited(db.close());
  }
}

/// Ids are fixed so tests can navigate to a specific record's route.
const seededProductId = 'prd_seed';
const seededCustomerId = 'cus_seed';
const seededExpenseId = 'exp_seed';

/// Boots the real app against an in-memory database with a signed-in account.
///
/// [withData] seeds one of every record so screens render their populated
/// state; pass false to exercise the empty states instead. [palette] brands
/// the run, so a test can prove the app still renders under a non-default
/// accent.
Future<AppHarness> bootApp(
  WidgetTester tester, {
  bool withData = true,
  Brightness brightness = Brightness.light,
  BrandPalette palette = BrandPalette.fallback,
}) async {
  const businessId = 'biz_seed';
  late final Database db;
  late final ProviderContainer container;

  // sqflite talks to a real database over an isolate. `testWidgets` runs its
  // body in a fake-async zone where that never completes, so every real await
  // has to happen inside `runAsync`.
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});

    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => SelloraDatabase.createSchema(db),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final auth = AuthController(db, prefs);
    await auth.register(
      name: 'Test Owner',
      username: 'owner',
      password: 'secret123',
    );

    await db.insert('businesses', {
      'id': businessId,
      'user_id': auth.state.userId,
      'name': 'Test Store',
      'type': 'Retail Store',
      'address': '12 Mabini St',
      'phone': '0917-000-0000',
      'created_at': 1,
    });

    if (withData) await _seed(db, businessId);

    final themeController = ThemeController(prefs);
    await themeController.set(
      brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    );
    final paletteController = BrandPaletteController(prefs);
    await paletteController.set(palette);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => db),
        authControllerProvider.overrideWith((ref) => auth),
        themeControllerProvider.overrideWith((ref) => themeController),
        brandPaletteProvider.overrideWith((ref) => paletteController),
      ],
    );
  });

  // A phone-sized surface. The default 800x600 test window is not a shape any
  // user has, and layout overflows only reproduce at realistic widths.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SelloraMobileApp(),
    ),
  );
  await settle(tester);

  return AppHarness._(db, container, businessId);
}

Future<void> _seed(Database db, String businessId) async {
  await db.insert('categories', {
    'id': 'cat_seed',
    'business_id': businessId,
    'name': 'Drinks',
    'created_at': 1,
  });
  await db.insert('products', {
    'id': seededProductId,
    'business_id': businessId,
    'category_id': 'cat_seed',
    'name': 'Bottled Water 500ml',
    'description': 'Chilled, sold by the piece.',
    'sku': 'W-500',
    'unit': 'pcs',
    'price': 25.0,
    'stock': 3, // low, so the low-stock styling renders
    'track_stock': 1,
    'active': 1,
    'created_at': 1,
  });
  await db.insert('products', {
    'id': 'prd_service',
    'business_id': businessId,
    'category_id': null,
    'name': 'Delivery Service',
    'description': '',
    'sku': '',
    'unit': 'hour',
    'price': 100.0,
    'stock': 0,
    'track_stock': 0, // untracked, so "Unlimited" renders
    'active': 0, // inactive, so the Inactive pill renders
    'created_at': 1,
  });
  await db.insert('customers', {
    'id': seededCustomerId,
    'business_id': businessId,
    'name': 'Aling Nena',
    'phone': '0917-111-2222',
    'email': 'nena@example.com',
    'notes': 'Prefers weekend delivery.',
    'created_at': 1,
  });
  await db.insert('sales', {
    'id': 'sal_seed',
    'business_id': businessId,
    'customer_id': seededCustomerId,
    'total': 50.0,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });
  await db.insert('sale_lines', {
    'id': 'lin_seed',
    'sale_id': 'sal_seed',
    'product_id': seededProductId,
    'name': 'Bottled Water 500ml',
    'qty': 2,
    'unit_price': 25.0,
  });
  await db.insert('stock_ledger', {
    'id': 'stk_seed',
    'business_id': businessId,
    'product_id': seededProductId,
    'delta': -2,
    'reason': 'sale',
    'ref_id': 'sal_seed',
    'note': '',
    'at': DateTime.now().millisecondsSinceEpoch,
  });
  await db.insert('expenses', {
    'id': seededExpenseId,
    'business_id': businessId,
    'amount': 250.0,
    'category': 'Supplies',
    'note': 'Weekly restock',
    'at': DateTime.now().millisecondsSinceEpoch,
  });
  await db.insert('refunds', {
    'id': 'ref_seed',
    'business_id': businessId,
    'sale_id': 'sal_seed',
    'amount': 25.0,
    'note': 'Damaged bottle',
    'restock': 1,
    'at': DateTime.now().millisecondsSinceEpoch,
  });
}

/// Pumps far enough for async providers backed by the real database to
/// deliver.
///
/// Alternates real time (so the sqflite futures actually resolve) with frames
/// (so the widget tree rebuilds on the new data). `pumpAndSettle` cannot be
/// used: several screens hold an indeterminate progress indicator, which never
/// settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Navigates to [location] and pumps, failing the test on any exception
/// thrown during build or layout — overflow assertions included.
Future<void> openRoute(
  WidgetTester tester,
  AppHarness harness,
  String location,
) async {
  harness.router.go(location);
  await settle(tester);
  expect(
    tester.takeException(),
    isNull,
    reason: 'Rendering $location threw',
  );
}
