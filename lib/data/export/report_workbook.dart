import 'package:excel/excel.dart';

import '../models/entities.dart';

/// Everything one exported report needs, gathered before any file is written.
///
/// A plain value rather than a repository call so [buildReportWorkbook] stays a
/// pure function of its input: the sheet layout, the totals and the row counts
/// are all testable without a database, a device, or a file system.
class ReportExportData {
  const ReportExportData({
    required this.businessName,
    required this.from,
    required this.to,
    required this.generatedAt,
    required this.revenue,
    required this.expenses,
    required this.transactions,
    required this.sales,
    required this.customerNames,
    required this.products,
    required this.expenseRows,
  });

  final String businessName;

  /// First day of the range, and the last — inclusive, as the owner picked
  /// them on screen. The exclusive bound is a query detail and does not belong
  /// in a document someone reads.
  final DateTime from;
  final DateTime to;

  final DateTime generatedAt;

  final double revenue;
  final double expenses;
  final int transactions;

  final List<Sale> sales;

  /// Customer id to name, so the sales sheet can say "Aling Nena" instead of
  /// `cus_7f3a`. Missing ids are walk-ins.
  final Map<String, String> customerNames;

  final List<({String name, int qty, double revenue})> products;
  final List<Expense> expenseRows;

  double get profit => revenue - expenses;
}

/// Builds the .xlsx bytes for one report.
///
/// Four sheets, in the order someone reads them: what happened, then the sales
/// that produced it, then the same money grouped by product, then what was
/// spent. Amounts are written as numbers, not strings, so the recipient can sum
/// a column without retyping it — the whole point of sending a spreadsheet
/// rather than a screenshot.
List<int> buildReportWorkbook(ReportExportData data) {
  final excel = Excel.createExcel();

  // createExcel() always seeds one sheet. Renaming it is safer than deleting
  // it: a workbook with no sheets is not a valid workbook.
  final seeded = excel.getDefaultSheet();
  if (seeded != null && seeded != _summary) {
    excel.rename(seeded, _summary);
  }

  _writeSummary(excel[_summary], data);
  _writeSales(excel[_sales], data);
  _writeProducts(excel[_products], data);
  _writeExpenses(excel[_expenses], data);

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('The spreadsheet could not be encoded.');
  }
  return bytes;
}

const _summary = 'Summary';
const _sales = 'Sales';
const _products = 'Products';
const _expenses = 'Expenses';

void _writeSummary(Sheet sheet, ReportExportData data) {
  sheet.appendRow([TextCellValue(data.businessName)]);
  sheet.appendRow([TextCellValue('Sellora report')]);
  sheet.appendRow(const []);

  _pair(sheet, 'Period from', DateTimeCellValue.fromDateTime(data.from));
  _pair(sheet, 'Period to', DateTimeCellValue.fromDateTime(data.to));
  _pair(sheet, 'Generated', DateTimeCellValue.fromDateTime(data.generatedAt));
  sheet.appendRow(const []);

  _pair(sheet, 'Revenue', DoubleCellValue(data.revenue));
  _pair(sheet, 'Expenses', DoubleCellValue(data.expenses));
  _pair(sheet, data.profit >= 0 ? 'Profit' : 'Loss',
      DoubleCellValue(data.profit));
  _pair(sheet, 'Sales recorded', IntCellValue(data.transactions));
  sheet.appendRow(const []);

  sheet.appendRow([
    TextCellValue('All amounts in pesos. Figures cover the period above only.'),
  ]);
}

void _pair(Sheet sheet, String label, CellValue value) {
  sheet.appendRow([TextCellValue(label), value]);
}

/// One row per sale line, not per sale.
///
/// A line is the unit anyone actually analyses — it is what a pivot table
/// groups by, and per-sale rows would bury the products inside a single cell.
/// The sale id repeats down the rows so the lines of one sale can still be
/// gathered back together.
void _writeSales(Sheet sheet, ReportExportData data) {
  sheet.appendRow([
    TextCellValue('Date'),
    TextCellValue('Sale ID'),
    TextCellValue('Customer'),
    TextCellValue('Product'),
    TextCellValue('Qty'),
    TextCellValue('Unit price'),
    TextCellValue('Line total'),
  ]);

  for (final sale in data.sales) {
    final when = DateTimeCellValue.fromDateTime(sale.createdAt);
    final who = TextCellValue(
      sale.customerId == null
          ? 'Walk-in'
          : data.customerNames[sale.customerId] ?? 'Walk-in',
    );

    if (sale.lines.isEmpty) {
      // Should not happen, but a sale that lost its lines still moved money.
      // Dropping the row would quietly make the sheet disagree with Summary.
      sheet.appendRow([
        when,
        TextCellValue(sale.id),
        who,
        TextCellValue('(no line items recorded)'),
        const IntCellValue(0),
        const DoubleCellValue(0),
        DoubleCellValue(sale.total),
      ]);
      continue;
    }

    for (final line in sale.lines) {
      sheet.appendRow([
        when,
        TextCellValue(sale.id),
        who,
        TextCellValue(line.name),
        IntCellValue(line.qty),
        DoubleCellValue(line.unitPrice),
        DoubleCellValue(line.qty * line.unitPrice),
      ]);
    }
  }
}

void _writeProducts(Sheet sheet, ReportExportData data) {
  sheet.appendRow([
    TextCellValue('Product'),
    TextCellValue('Units sold'),
    TextCellValue('Revenue'),
  ]);
  for (final p in data.products) {
    sheet.appendRow([
      TextCellValue(p.name),
      IntCellValue(p.qty),
      DoubleCellValue(p.revenue),
    ]);
  }
}

void _writeExpenses(Sheet sheet, ReportExportData data) {
  sheet.appendRow([
    TextCellValue('Date'),
    TextCellValue('Category'),
    TextCellValue('Note'),
    TextCellValue('Amount'),
  ]);
  for (final e in data.expenseRows) {
    sheet.appendRow([
      DateTimeCellValue.fromDateTime(e.at),
      TextCellValue(e.category),
      TextCellValue(e.note),
      DoubleCellValue(e.amount),
    ]);
  }
}

/// A file name that sorts chronologically and says what it is at a glance,
/// once it is sitting in someone's Downloads folder among a hundred others.
String reportFileName(String businessName, DateTime from, DateTime to) {
  final slug = businessName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final name = slug.isEmpty ? 'sellora' : slug;
  return '$name-report-${_stamp(from)}-to-${_stamp(to)}.xlsx';
}

String _stamp(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';
