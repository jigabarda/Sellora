import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/dates.dart';
import '../repositories/business_repository.dart';
import '../repositories/customer_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/sale_repository.dart';
import 'report_workbook.dart';

/// Gathers a period's figures and writes them out as a spreadsheet.
///
/// Everything stays on-device. The file leaves the app only through the system
/// share sheet, exactly as the backup does — which is also why it is written to
/// the cache directory and needs no storage permission. Sellora asks for none,
/// and an export is not a reason to start.
class ReportExportService {
  ReportExportService({
    required SaleRepository sales,
    required ExpenseRepository expenses,
    required CustomerRepository customers,
    required BusinessRepository businesses,
  })  : _sales = sales,
        _expenses = expenses,
        _customers = customers,
        _businesses = businesses;

  final SaleRepository _sales;
  final ExpenseRepository _expenses;
  final CustomerRepository _customers;
  final BusinessRepository _businesses;

  /// Collects everything the workbook needs for [from]..[to], both inclusive.
  Future<ReportExportData> gather({
    required String businessId,
    required DateTime from,
    required DateTime to,
    required DateTime generatedAt,
  }) async {
    // The screen speaks in inclusive days; the queries want a half-open range.
    // Converting once, here, keeps that off-by-one in a single place.
    final toExclusive = addDays(to, 1);

    final business = await _businesses.getById(businessId);
    final sales = await _sales.listBetween(businessId, from, toExclusive);
    final revenue = await _sales.sumBetween(businessId, from, toExclusive);
    final spent = await _expenses.sumBetween(businessId, from, toExclusive);
    final products =
        await _sales.productPerformance(businessId, from, toExclusive);
    final expenseRows =
        await _expenses.listBetween(businessId, from, toExclusive);
    final customers = await _customers.listForBusiness(businessId);

    return ReportExportData(
      businessName: business?.name ?? 'Sellora',
      from: from,
      to: to,
      generatedAt: generatedAt,
      revenue: revenue,
      expenses: spent,
      // Counted from the rows themselves rather than a second COUNT query, so
      // the number in Summary can never disagree with the Sales sheet below it.
      transactions: sales.length,
      sales: sales,
      customerNames: {for (final c in customers) c.id: c.name},
      products: products,
      expenseRows: expenseRows,
    );
  }

  /// The finished spreadsheet and the name it should carry.
  ///
  /// Both destinations start here: saving to Downloads hands the bytes
  /// straight to MediaStore, while sharing needs them on disk first.
  Future<({String fileName, Uint8List bytes})> buildReport({
    required String businessId,
    required DateTime from,
    required DateTime to,
    required DateTime generatedAt,
  }) async {
    final data = await gather(
      businessId: businessId,
      from: from,
      to: to,
      generatedAt: generatedAt,
    );
    return (
      fileName: reportFileName(data.businessName, from, to),
      bytes: Uint8List.fromList(buildReportWorkbook(data)),
    );
  }

  /// Writes the report to the cache directory and returns the file.
  ///
  /// Cache is deliberate: the copy is a hand-off for the share sheet, not
  /// storage. Wherever the user sends it is the real copy.
  Future<File> writeReportFile({
    required String businessId,
    required DateTime from,
    required DateTime to,
    required DateTime generatedAt,
  }) async {
    final report = await buildReport(
      businessId: businessId,
      from: from,
      to: to,
      generatedAt: generatedAt,
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${report.fileName}');
    await file.writeAsBytes(report.bytes, flush: true);
    return file;
  }
}
