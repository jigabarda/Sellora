import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/core/brand_palette.dart';
import 'package:sellora_mobile/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Every route reachable from the signed-in app.
List<({String name, String path})> routesFor(String bizId) => [
      (name: 'home', path: '/'),
      (name: 'new business', path: '/business/new'),
      (name: 'backup', path: '/backup'),
      (name: 'dashboard', path: '/business/$bizId/dashboard'),
      (name: 'products', path: '/business/$bizId/products'),
      (name: 'new product', path: '/business/$bizId/products/new'),
      (
        name: 'edit product',
        path: '/business/$bizId/products/edit/$seededProductId'
      ),
      (name: 'sales', path: '/business/$bizId/sales'),
      (name: 'new sale', path: '/business/$bizId/sales/new'),
      (name: 'more', path: '/business/$bizId/more'),
      (name: 'customers', path: '/business/$bizId/customers'),
      (name: 'new customer', path: '/business/$bizId/customers/new'),
      (
        name: 'edit customer',
        path: '/business/$bizId/customers/edit/$seededCustomerId'
      ),
      (name: 'categories', path: '/business/$bizId/categories'),
      (name: 'inventory', path: '/business/$bizId/inventory'),
      (name: 'expenses', path: '/business/$bizId/expenses'),
      (name: 'new expense', path: '/business/$bizId/expenses/new'),
      (
        name: 'edit expense',
        path: '/business/$bizId/expenses/edit/$seededExpenseId'
      ),
      (name: 'refunds', path: '/business/$bizId/refunds'),
      (name: 'new refund', path: '/business/$bizId/refunds/new'),
      (name: 'quick entry', path: '/business/$bizId/quick'),
      (name: 'insights', path: '/business/$bizId/insights'),
      (name: 'reports', path: '/business/$bizId/reports'),
      (name: 'settings', path: '/business/$bizId/settings'),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('renders with data', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final mode = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('every screen builds in $mode mode', (tester) async {
        final harness = await bootApp(tester, brightness: brightness);
        addTearDown(harness.dispose);

        for (final route in routesFor(harness.businessId)) {
          await openRoute(tester, harness, route.path);
        }
      });
    }
  });

  testWidgets('every screen builds with no data at all', (tester) async {
    // Empty states are the least-exercised path and the easiest to break,
    // since providers deliver empty lists rather than null.
    final harness = await bootApp(tester, withData: false);
    addTearDown(harness.dispose);

    for (final route in routesFor(harness.businessId)) {
      // The record-specific routes have nothing to open without seed data.
      if (route.path.contains('/edit/')) continue;
      await openRoute(tester, harness, route.path);
    }
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('logged-out routes build in $mode mode', (tester) async {
      final harness = await bootApp(tester, brightness: brightness);
      addTearDown(harness.dispose);

      await harness.container.read(authControllerProvider.notifier).logout();
      await settle(tester);

      for (final path in ['/welcome', '/login', '/register']) {
        await openRoute(tester, harness, path);
      }
    });
  }

  testWidgets('an unknown route shows the not-found screen', (tester) async {
    final harness = await bootApp(tester);
    addTearDown(harness.dispose);

    await openRoute(tester, harness, '/business/${harness.businessId}/nope');
    expect(find.text('This page does not exist'), findsOneWidget);
  });

  testWidgets('a business id that does not exist does not crash',
      (tester) async {
    // Reachable from a stale deep link or a backup restored on another device.
    final harness = await bootApp(tester);
    addTearDown(harness.dispose);

    await openRoute(tester, harness, '/business/biz_missing/dashboard');
    await openRoute(tester, harness, '/business/biz_missing/products');
    await openRoute(tester, harness, '/business/biz_missing/settings');
  });

  // The accent feeds computed values — `accentSoft` is composited and
  // `onAccent` is chosen by luminance — so a palette at the light end of the
  // range exercises a different branch than the default indigo does.
  for (final palette in [BrandPalette.amber, BrandPalette.graphite]) {
    testWidgets('every screen builds branded ${palette.name}', (tester) async {
      final harness = await bootApp(tester, palette: palette);
      addTearDown(harness.dispose);

      for (final route in routesFor(harness.businessId)) {
        await openRoute(tester, harness, route.path);
      }
    });
  }
}
