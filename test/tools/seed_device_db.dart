import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/auth/auth_controller.dart';
import 'package:sellora_mobile/data/db/sellora_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Not a test — a generator, parked in `test/` because that is the only place
/// the Flutter toolchain will run Dart with the project's dependencies
/// available.
///
/// Produces a `sellora.db` populated the way a real account looks after a few
/// weeks of trading, so the list screens can be reviewed on a device with
/// content in them instead of empty states. Push it with:
///
///   adb root
///   adb push build/seed/sellora.db \
///     /data/data/com.sellora.mobile/app_flutter/sellora.db
///   adb shell chown u0_aNNN:u0_aNNN /data/data/.../sellora.db
///
/// Then sign in as `juandc` / `secret123`.
///
/// The filename deliberately omits the `_test` suffix, so `flutter test` never
/// picks it up and no ordinary test run writes files. Run it explicitly:
///
///   flutter test test/tools/seed_device_db.dart
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('writes a seeded database to build/seed/sellora.db', () async {
    SharedPreferences.setMockInitialValues({});

    // Absolute, because sqflite's ffi factory does not resolve a relative
    // path against the same working directory `dart:io` does — which silently
    // put the database somewhere other than where this looked for it.
    final dir = Directory('${Directory.current.path}/build/seed');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final path = '${dir.path}/sellora.db';
    // ignore: avoid_print
    print('Writing to $path');

    // Opened through the production options rather than a hand-rolled
    // OpenDatabaseOptions, so the file is stamped with the current
    // `user_version`. Creating it at version 1 leaves the app convinced it has
    // an ancient database on next launch: it runs the v1 migration over a
    // schema that already has every table, throws inside `main` before
    // `runApp`, and the process hangs with no window at all — which surfaces
    // as "Sellora isn't responding" rather than anything resembling a crash.
    final db = await databaseFactory.openDatabase(
      path,
      options: SelloraDatabase.openOptions(),
    );

    final auth = AuthController(db, await SharedPreferences.getInstance());
    await auth.register(
      name: 'Juan Dela Cruz',
      username: 'juandc',
      password: 'secret123',
    );
    final userId = auth.state.userId!;

    const bizId = 'biz_seed';
    final now = DateTime.now();
    int at(int daysAgo) =>
        now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

    await db.insert('businesses', {
      'id': bizId,
      'user_id': userId,
      'name': 'Juan Water Refilling',
      'type': 'Water Station',
      'address': '12 Mabini St, Cavite',
      'phone': '0917-555-0101',
      // Backdated past the eight weeks of trading below. A business created
      // today with two months of sales against it is incoherent, and it also
      // suppresses the profit rule, whose gate requires a full week of history.
      'created_at': at(120),
    });

    const categories = [
      ('cat_water', 'Water'),
      ('cat_ice', 'Ice'),
      ('cat_svc', 'Services'),
    ];
    for (final (id, name) in categories) {
      await db.insert('categories', {
        'id': id,
        'business_id': bizId,
        'name': name,
        'created_at': at(60),
      });
    }

    // Deliberately mixed: low stock, healthy stock, an untracked service and
    // an inactive line, so every row variant on Products and Inventory has
    // something to render.
    const products = [
      (
        'prd_1',
        'cat_water',
        'Purified 5-Gallon Refill',
        'W-5G',
        25.0,
        42,
        'pcs',
        1,
        1
      ),
      (
        'prd_2',
        'cat_water',
        'Distilled 5-Gallon Refill',
        'W-5D',
        30.0,
        3,
        'pcs',
        1,
        1
      ),
      (
        'prd_3',
        'cat_water',
        'Alkaline 1L Bottle',
        'W-1A',
        45.0,
        18,
        'pcs',
        1,
        1
      ),
      ('prd_4', 'cat_ice', 'Crushed Ice Bag', 'I-CR', 60.0, 2, 'kg', 1, 1),
      ('prd_5', 'cat_ice', 'Ice Tube Sack', 'I-TB', 120.0, 25, 'sack', 1, 1),
      ('prd_6', 'cat_svc', 'Home Delivery', 'SVC-D', 50.0, 0, 'trip', 0, 1),
      ('prd_7', 'cat_svc', 'Container Cleaning', 'SVC-C', 80.0, 0, 'pcs', 0, 1),
      ('prd_8', null, 'Old Blue Container', 'C-OLD', 250.0, 0, 'pcs', 1, 0),
      ('prd_9', null, 'Blue Drum 20L', 'D-20', 320.0, 4, 'pcs', 1, 1),
    ];
    for (final p in products) {
      await db.insert('products', {
        'id': p.$1,
        'business_id': bizId,
        'category_id': p.$2,
        'name': p.$3,
        'description': '',
        'sku': p.$4,
        'price': p.$5,
        'stock': p.$6,
        'unit': p.$7,
        'track_stock': p.$8,
        'active': p.$9,
        'created_at': at(50),
      });
    }

    const customers = [
      ('cus_1', 'Aling Nena', '0917-111-2222', 'nena@example.com'),
      ('cus_2', 'Mang Tonyo', '0918-333-4444', ''),
      ('cus_3', 'Sari-Sari ni Ate Baby', '0920-555-6666', 'baby@example.com'),
      ('cus_4', 'Carinderia Malaya', '0921-777-8888', ''),
      ('cus_5', 'Jollibee Branch 12', '0922-999-0000', 'b12@example.com'),
      ('cus_6', 'Roberto Santos', '0915-222-3333', ''),
      ('cus_7', 'Tindahan ni Mareng Rosa', '0919-444-5555', ''),
    ];
    for (final c in customers) {
      await db.insert('customers', {
        'id': c.$1,
        'business_id': bizId,
        'name': c.$2,
        'phone': c.$3,
        'email': c.$4,
        'notes': '',
        'created_at': at(40),
      });
    }

    // Sales spread over recent days so the dashboard's today/week figures and
    // the Sales screen's day grouping both have something to show.
    const sales = [
      ('sal_1', 'cus_1', 0, 'prd_1', 2, 25.0),
      ('sal_2', 'cus_3', 0, 'prd_5', 1, 120.0),
      ('sal_3', null, 0, 'prd_3', 3, 45.0),
      ('sal_4', 'cus_2', 1, 'prd_1', 4, 25.0),
      ('sal_5', 'cus_5', 1, 'prd_4', 2, 60.0),
      ('sal_6', 'cus_4', 3, 'prd_2', 1, 30.0),
      ('sal_7', 'cus_6', 5, 'prd_6', 1, 50.0),
    ];
    for (final s in sales) {
      final total = s.$5 * s.$6;
      await db.insert('sales', {
        'id': s.$1,
        'business_id': bizId,
        'customer_id': s.$2,
        'total': total,
        'created_at': at(s.$3),
      });
      await db.insert('sale_lines', {
        'id': 'ln_${s.$1}',
        'sale_id': s.$1,
        'product_id': s.$4,
        'name': products.firstWhere((p) => p.$1 == s.$4).$3,
        'qty': s.$5,
        'unit_price': s.$6,
      });
      await db.insert('stock_ledger', {
        'id': 'stk_${s.$1}',
        'business_id': bizId,
        'product_id': s.$4,
        'delta': -s.$5,
        'reason': 'sale',
        'ref_id': s.$1,
        'note': '',
        'at': at(s.$3),
      });
    }

    // Eight weeks of trading, shaped so the insight rules have real
    // distributions to find rather than a handful of hand-placed rows. Without
    // this every rule correctly stays silent, which makes the feature
    // impossible to review on a device.
    //
    // Tuesdays are deliberately dead and Saturdays busy, so the day-of-week
    // rule has a genuine gap to detect.
    var seq = 0;
    Future<void> record(
      String productId,
      int qty,
      double unitPrice,
      DateTime on, {
      String? customerId,
      bool refunded = false,
    }) async {
      seq++;
      final id = 'sal_h$seq';
      final stamp = on.millisecondsSinceEpoch;
      await db.insert('sales', {
        'id': id,
        'business_id': bizId,
        'customer_id': customerId,
        'total': qty * unitPrice,
        'created_at': stamp,
      });
      await db.insert('sale_lines', {
        'id': 'ln_$id',
        'sale_id': id,
        'product_id': productId,
        'name': products.firstWhere((p) => p.$1 == productId).$3,
        'qty': qty,
        'unit_price': unitPrice,
      });
      await db.insert('stock_ledger', {
        'id': 'stk_$id',
        'business_id': bizId,
        'product_id': productId,
        'delta': -qty,
        'reason': 'sale',
        'ref_id': id,
        'note': '',
        'at': stamp,
      });
      if (refunded) {
        await db.insert('refunds', {
          'id': 'ref_$id',
          'business_id': bizId,
          'sale_id': id,
          'amount': qty * unitPrice,
          'note': 'Melted on arrival',
          'restock': 0,
          'at': stamp,
        });
      }
    }

    for (var daysAgo = 56; daysAgo >= 0; daysAgo--) {
      final day = now.subtract(Duration(days: daysAgo));
      if (day.weekday == DateTime.tuesday) continue;
      final at12 = DateTime(day.year, day.month, day.day, 12);
      final busy = day.weekday == DateTime.saturday;
      await record('prd_1', busy ? 6 : 2, 25.0, at12);
      if (busy) await record('prd_3', 2, 45.0, at12);
    }

    // Two products heading for zero at different speeds, so both severity
    // levels of the run-out rule appear.
    for (final daysAgo in [1, 3, 5]) {
      final day = _skipTuesday(now.subtract(Duration(days: daysAgo)));
      await record('prd_2', 3, 30.0, DateTime(day.year, day.month, day.day, 9));
      await record(
          'prd_4', 5, 60.0, DateTime(day.year, day.month, day.day, 15));
    }

    // Enough Crushed Ice sales to clear the refund gate, two of them returned.
    for (final daysAgo in [8, 10, 12]) {
      final day = _skipTuesday(now.subtract(Duration(days: daysAgo)));
      await record(
        'prd_4',
        1,
        60.0,
        DateTime(day.year, day.month, day.day, 11),
        refunded: daysAgo != 12,
      );
    }

    // A weekly regular who then stopped, for the quiet-customer rule. Uses its
    // own customer because every other seeded customer has a sale from this
    // week, which would correctly disqualify them.
    for (final daysAgo in [60, 53, 46, 39]) {
      final day = _skipTuesday(now.subtract(Duration(days: daysAgo)));
      await record('prd_1', 2, 25.0, DateTime(day.year, day.month, day.day, 10),
          customerId: 'cus_7');
    }

    const expenses = [
      ('exp_1', 1200.0, 'Supplies', 'Bottle caps and seals', 1),
      ('exp_2', 3400.0, 'Utilities', 'Electricity — February', 2),
      ('exp_3', 8000.0, 'Rent', 'Stall rent', 4),
      ('exp_4', 750.0, 'Transport', 'Delivery fuel', 5),
      ('exp_5', 5000.0, 'Payroll', 'Helper wages', 6),
      ('exp_6', 320.0, 'Other', 'Permit photocopy', 8),
    ];
    for (final e in expenses) {
      await db.insert('expenses', {
        'id': e.$1,
        'business_id': bizId,
        'amount': e.$2,
        'category': e.$3,
        'note': e.$4,
        'at': at(e.$5),
      });
    }

    await db.insert('refunds', {
      'id': 'ref_1',
      'business_id': bizId,
      'sale_id': 'sal_2',
      'amount': 120.0,
      'note': 'Melted on arrival',
      'restock': 0,
      'at': at(1),
    });
    await db.insert('refunds', {
      'id': 'ref_2',
      'business_id': bizId,
      'sale_id': null,
      'amount': 25.0,
      'note': 'Wrong item handed over',
      'restock': 1,
      'at': at(3),
    });

    await db.insert('stock_ledger', {
      'id': 'stk_restock',
      'business_id': bizId,
      'product_id': 'prd_1',
      'delta': 60,
      'reason': 'purchase',
      'ref_id': null,
      'note': 'Weekly delivery',
      'at': at(7),
    });

    await db.close();

    expect(File(path).existsSync(), isTrue);
    // ignore: avoid_print
    print('Seeded database written to $path');
  });
}

/// Nudges a date off Tuesday, which the eight-week loop above leaves empty on
/// purpose so the day-of-week rule has an unambiguous slowest day.
DateTime _skipTuesday(DateTime day) => day.weekday == DateTime.tuesday
    ? day.subtract(const Duration(days: 1))
    : day;
