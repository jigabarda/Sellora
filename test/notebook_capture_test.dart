import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sellora_mobile/data/notebook/text_recogniser.dart';
import 'package:sellora_mobile/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Returns a fixed page, so the capture flow runs without a camera or a model.
class _FixedRecogniser implements TextRecogniser {
  const _FixedRecogniser(this.text);

  final String text;

  @override
  Future<String> recognise(String imagePath) async => text;

  @override
  Future<void> dispose() async {}
}

Future<String?> _alwaysPicks(ImageSource source) async => 'page.jpg';

Future<int> _saleCount(WidgetTester tester, AppHarness harness) async {
  final rows = await tester.runAsync(
    () => harness.db.rawQuery('SELECT COUNT(*) c FROM sales'),
  );
  return (rows!.first['c'] as num).toInt();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // The seeded product is Bottled Water 500ml, ₱25, three in stock. Two lines
  // of two is one more than the shelf holds, so the first line goes in and the
  // second cannot — the partial failure this screen has to survive.
  const page = 'Nena 2 water 50\n2 water 50';

  Future<AppHarness> openPreview(WidgetTester tester) async {
    final harness = await bootApp(
      tester,
      overrides: [
        textRecogniserProvider.overrideWithValue(const _FixedRecogniser(page)),
        imagePickerProvider.overrideWithValue(_alwaysPicks),
      ],
    );
    addTearDown(harness.dispose);
    await openRoute(tester, harness, '/business/${harness.businessId}/scan');
    await tester.tap(find.text('Choose an existing photo'));
    await settle(tester);
    return harness;
  }

  testWidgets('both lines prove themselves, so both start ticked',
      (tester) async {
    await openPreview(tester);
    expect(find.text('2 of 2 lines added up'), findsOneWidget);
    expect(find.text('Record 2 sales'), findsOneWidget);
  });

  testWidgets('reading the page writes nothing on its own', (tester) async {
    final harness = await openPreview(tester);
    // The whole design rests on this: recognition produces a preview and
    // nothing else. Only the tap on Record may touch the database.
    expect(await _saleCount(tester, harness), 1); // the seeded sale, untouched
  });

  testWidgets('the lines that fit the shelf still go in', (tester) async {
    final harness = await openPreview(tester);
    final before = await _saleCount(tester, harness);

    await tester.tap(find.text('Record 2 sales'));
    await settle(tester);

    expect(await _saleCount(tester, harness), before + 1);
    expect(find.textContaining('Could not record 1'), findsOneWidget);
  });

  testWidgets('a line already in the books cannot be recorded twice',
      (tester) async {
    final harness = await openPreview(tester);

    await tester.tap(find.text('Record 2 sales'));
    await settle(tester);
    final afterFirstRecord = await _saleCount(tester, harness);

    // The line that went in is marked, and the tally now counts what is done
    // rather than what originally added up.
    expect(find.text('Recorded'), findsOneWidget);
    expect(find.text('1 recorded · 1 left on this page'), findsOneWidget);

    // The regression this guards. The recorded line is still on screen next to
    // the one that failed, so if it were selectable the owner could restock,
    // tick the page again, and write the same sale to the books a second time.
    await tester.tap(find.text('Nena 2 water 50'));
    await settle(tester);

    expect(find.text('Nothing selected'), findsOneWidget);
    expect(await _saleCount(tester, harness), afterFirstRecord);
  });
}
