import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/export/report_workbook.dart';
import 'package:sellora_mobile/data/models/entities.dart';

/// The workbook builder is pure, so these are real assertions about a real
/// .xlsx: every test below encodes a workbook and decodes it back, which is the
/// only way to know the file a bookkeeper opens is the file we meant to write.

final _epoch = DateTime(2026, 8, 10, 9, 30);

SaleLine _line(String saleId, String name, int qty, double price) => SaleLine(
      id: 'ln_${saleId}_$name',
      saleId: saleId,
      productId: 'prd_$name',
      name: name,
      qty: qty,
      unitPrice: price,
    );

Sale _sale(
  String id, {
  String? customerId,
  required double total,
  required List<SaleLine> lines,
  DateTime? at,
}) =>
    Sale(
      id: id,
      businessId: 'biz',
      customerId: customerId,
      total: total,
      createdAt: at ?? _epoch,
      lines: lines,
    );

ReportExportData _data({
  List<Sale>? sales,
  List<Expense>? expenses,
  List<({String name, int qty, double revenue})>? products,
  Map<String, String>? customers,
  double revenue = 300,
  double spent = 100,
  String businessName = 'Juan Water Refilling',
}) =>
    ReportExportData(
      businessName: businessName,
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 31),
      generatedAt: _epoch,
      revenue: revenue,
      expenses: spent,
      transactions: (sales ?? const []).length,
      sales: sales ??
          [
            _sale('sal_1',
                customerId: 'cus_1',
                total: 50,
                lines: [_line('sal_1', 'Purified Refill', 2, 25)]),
          ],
      customerNames: customers ?? const {'cus_1': 'Aling Nena'},
      products: products ??
          const [(name: 'Purified Refill', qty: 2, revenue: 50.0)],
      expenseRows: expenses ?? const [],
    );

Excel _roundTrip(ReportExportData data) =>
    Excel.decodeBytes(buildReportWorkbook(data));

/// A numeric cell's value, whichever numeric cell it turned out to be.
///
/// The encoder normalises a whole-numbered double to an int cell on the way
/// out, so `50.0` decodes as `IntCellValue(50)`. That is invisible in Excel and
/// irrelevant to the requirement, which is only that the cell is a *number* and
/// not text — a column of text cannot be summed, and that is the whole reason
/// for sending a spreadsheet instead of a screenshot.
num _number(CellValue? cell) {
  expect(cell, anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()),
      reason: 'money must be a numeric cell, not text');
  return switch (cell) {
    IntCellValue(:final value) => value,
    DoubleCellValue(:final value) => value,
    _ => throw StateError('not numeric: $cell'),
  };
}

void main() {
  test('produces a workbook that decodes back, with the four sheets', () {
    final book = _roundTrip(_data());
    expect(
      book.tables.keys.toSet(),
      {'Summary', 'Sales', 'Products', 'Expenses'},
    );
  });

  test('the seeded default sheet does not survive as an empty extra', () {
    final book = _roundTrip(_data());
    // Excel.createExcel() always seeds one sheet; if it were left alone the
    // recipient would open a stray "Sheet1" before reaching anything real.
    expect(book.tables.containsKey('Sheet1'), isFalse);
  });

  test('one row per sale line, not per sale', () {
    final data = _data(sales: [
      _sale('sal_1', customerId: 'cus_1', total: 170, lines: [
        _line('sal_1', 'Purified Refill', 2, 25),
        _line('sal_1', 'Ice Tube Sack', 1, 120),
      ]),
      _sale('sal_2', total: 25, lines: [_line('sal_2', 'Purified Refill', 1, 25)]),
    ]);

    final rows = _roundTrip(data).tables['Sales']!.rows;
    // Header plus three lines across two sales.
    expect(rows.length, 4);
    expect(rows[1][1]?.value, isA<TextCellValue>());
  });

  test('amounts are numbers, so a column can be summed without retyping', () {
    final rows = _roundTrip(_data()).tables['Sales']!.rows;
    expect(_number(rows[1].last!.value), 50);
  });

  test('a sale that lost its lines still appears, carrying its total', () {
    final data = _data(sales: [
      _sale('sal_orphan', total: 90, lines: const []),
    ]);

    final rows = _roundTrip(data).tables['Sales']!.rows;
    expect(rows.length, 2);
    // Dropping it would make the Sales sheet quietly disagree with Summary.
    expect(_number(rows[1].last!.value), 90);
  });

  test('a customer id resolves to a name, and an unknown one is a walk-in', () {
    final data = _data(
      sales: [
        _sale('sal_1',
            customerId: 'cus_1',
            total: 25,
            lines: [_line('sal_1', 'Refill', 1, 25)]),
        _sale('sal_2',
            customerId: 'cus_gone',
            total: 25,
            lines: [_line('sal_2', 'Refill', 1, 25)]),
        _sale('sal_3', total: 25, lines: [_line('sal_3', 'Refill', 1, 25)]),
      ],
      customers: const {'cus_1': 'Aling Nena'},
    );

    final rows = _roundTrip(data).tables['Sales']!.rows;
    expect((rows[1][2]!.value as TextCellValue).value.toString(), 'Aling Nena');
    // A customer deleted since the sale must not print a raw id at someone.
    expect((rows[2][2]!.value as TextCellValue).value.toString(), 'Walk-in');
    expect((rows[3][2]!.value as TextCellValue).value.toString(), 'Walk-in');
  });

  test('expenses carry their own sheet', () {
    final data = _data(expenses: [
      Expense(
        id: 'exp_1',
        businessId: 'biz',
        amount: 120,
        category: 'Delivery',
        note: 'tricycle',
        at: _epoch,
      ),
    ]);

    final rows = _roundTrip(data).tables['Expenses']!.rows;
    expect(rows.length, 2);
    expect(_number(rows[1][3]!.value), 120);
  });

  test('Filipino text and punctuation survive the round trip', () {
    // Names here carry n-with-tilde and the peso sign, and notes get typed with
    // dashes. A mangled character in a document handed to a bookkeeper looks
    // like a broken app, so this is a requirement, not a nicety.
    const note = 'Kuryente — Peñafrancia ₱500';
    final data = _data(
      businessName: 'Tindahan ni Año',
      expenses: [
        Expense(
          id: 'exp_1',
          businessId: 'biz',
          amount: 500,
          category: 'Kuryente',
          note: note,
          at: _epoch,
        ),
      ],
    );

    final rows = _roundTrip(data).tables['Expenses']!.rows;
    expect((rows[1][2]!.value as TextCellValue).value.toString(), note);
    expect(
      reportFileName('Tindahan ni Año', DateTime(2026, 1, 1),
          DateTime(2026, 1, 2)),
      'tindahan-ni-a-o-report-20260101-to-20260102.xlsx',
    );
  });

  test('summary reports a loss as a loss', () {
    final book = _roundTrip(_data(revenue: 100, spent: 250));
    final labels = book.tables['Summary']!.rows
        .map((r) => r.isEmpty ? '' : '${r.first?.value ?? ''}')
        .toList();
    expect(labels, contains('Loss'));
    expect(labels, isNot(contains('Profit')));
  });

  test('empty period still produces a readable file rather than failing', () {
    final data = _data(sales: const [], products: const [], expenses: const []);
    final book = _roundTrip(data);
    // Headers only — an empty report is an answer, not an error.
    expect(book.tables['Sales']!.rows.length, 1);
    expect(book.tables['Products']!.rows.length, 1);
  });

  group('file name', () {
    test('sorts chronologically and says what it is', () {
      expect(
        reportFileName(
            'Juan Water Refilling', DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
        'juan-water-refilling-report-20260801-to-20260831.xlsx',
      );
    });

    test('survives a business name that is all punctuation', () {
      expect(
        reportFileName('!!!', DateTime(2026, 1, 2), DateTime(2026, 1, 3)),
        'sellora-report-20260102-to-20260103.xlsx',
      );
    });
  });
}
