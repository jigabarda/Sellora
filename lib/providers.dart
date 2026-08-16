import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'core/dates.dart';
import 'data/auth/auth_controller.dart';
import 'data/backup/backup_service.dart';
import 'data/insights/insight.dart';
import 'data/insights/insights_service.dart';
import 'data/models/entities.dart';
import 'data/notebook/text_recogniser.dart';
import 'data/repositories/business_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/refund_repository.dart';
import 'data/repositories/sale_repository.dart';

/// Overridden in `main.dart` after the database file is opened.
final databaseProvider = Provider<Database>(
  (ref) =>
      throw StateError('databaseProvider must be overridden in ProviderScope'),
);

/// Overridden in `main.dart` after SharedPreferences + DB are ready.
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => throw StateError(
      'authControllerProvider must be overridden in ProviderScope'),
);

final businessRepositoryProvider = Provider<BusinessRepository>(
  (ref) => BusinessRepository(ref.watch(databaseProvider)),
);

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(databaseProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(databaseProvider)),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(databaseProvider)),
);

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => SaleRepository(ref.watch(databaseProvider)),
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(databaseProvider)),
);

final refundRepositoryProvider = Provider<RefundRepository>(
  (ref) => RefundRepository(ref.watch(databaseProvider)),
);

final insightsServiceProvider = Provider<InsightsService>(
  (ref) => InsightsService(ref.watch(databaseProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);

/// On-device text recognition for photographed ledger pages.
///
/// A provider so tests can substitute a recogniser that returns fixed text —
/// the widget layer must be exercisable without a camera. Disposed with the
/// scope so the native recogniser does not outlive the app's use of it.
final textRecogniserProvider = Provider<TextRecogniser>((ref) {
  final recogniser = MlKitTextRecogniser();
  ref.onDispose(recogniser.dispose);
  return recogniser;
});

final currentUserProvider = FutureProvider.autoDispose<LocalUser?>((ref) async {
  // Watched, not read: signing in or out has to re-resolve this.
  ref.watch(authControllerProvider);
  return ref.watch(authControllerProvider.notifier).currentUser();
});

final businessesProvider =
    FutureProvider.autoDispose<List<Business>>((ref) async {
  final uid = ref.watch(authControllerProvider).userId;
  if (uid == null) return [];
  return ref.watch(businessRepositoryProvider).listForUser(uid);
});

final businessProvider =
    FutureProvider.autoDispose.family<Business?, String>((ref, id) async {
  return ref.watch(businessRepositoryProvider).getById(id);
});

final productsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>((ref, businessId) async {
  return ref.watch(productRepositoryProvider).listForBusiness(businessId);
});

final categoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, String>((ref, businessId) async {
  return ref.watch(categoryRepositoryProvider).listForBusiness(businessId);
});

/// Product counts per category, for the categories manager.
final categoryUsageProvider = FutureProvider.autoDispose
    .family<Map<String, int>, String>((ref, businessId) async {
  return ref.watch(categoryRepositoryProvider).productCounts(businessId);
});

final customersProvider = FutureProvider.autoDispose
    .family<List<Customer>, String>((ref, businessId) async {
  return ref.watch(customerRepositoryProvider).listForBusiness(businessId);
});

final salesProvider = FutureProvider.autoDispose
    .family<List<Sale>, String>((ref, businessId) async {
  return ref.watch(saleRepositoryProvider).listRecent(businessId);
});

final expensesProvider = FutureProvider.autoDispose
    .family<List<Expense>, String>((ref, businessId) async {
  return ref.watch(expenseRepositoryProvider).listForBusiness(businessId);
});

final refundsProvider = FutureProvider.autoDispose
    .family<List<Refund>, String>((ref, businessId) async {
  return ref.watch(refundRepositoryProvider).listForBusiness(businessId);
});

final stockLedgerProvider = FutureProvider.autoDispose
    .family<List<StockLedgerEntry>, String>((ref, businessId) async {
  return ref.watch(productRepositoryProvider).ledgerForBusiness(businessId);
});

class DashboardStats {
  const DashboardStats({
    required this.todaySales,
    required this.weekSales,
    required this.activeProducts,
    required this.transactions,
    required this.lowStockCount,
  });

  final double todaySales;
  final double weekSales;
  final int activeProducts;
  final int transactions;
  final int lowStockCount;
}

final dashboardStatsProvider = FutureProvider.autoDispose
    .family<DashboardStats, String>((ref, businessId) async {
  final sales = ref.watch(saleRepositoryProvider);
  final products = ref.watch(productRepositoryProvider);

  final todayStart = startOfTodayLocal();
  final tomorrow = addDays(todayStart, 1);
  final weekStart = startOfWeekMondayLocal();
  final nextWeek = addDays(weekStart, 7);

  final todaySales = await sales.sumBetween(businessId, todayStart, tomorrow);
  final weekSales = await sales.sumBetween(businessId, weekStart, nextWeek);
  final activeProducts = await products.countActive(businessId);
  final transactions = await sales.countForBusiness(businessId);
  final low = await products.listLowStock(businessId, threshold: 5);

  return DashboardStats(
    todaySales: todaySales,
    weekSales: weekSales,
    activeProducts: activeProducts,
    transactions: transactions,
    lowStockCount: low.length,
  );
});

class ReportSummary {
  const ReportSummary({
    required this.revenue,
    required this.expenses,
    required this.profit,
    required this.transactions,
    required this.topProducts,
  });

  final double revenue;
  final double expenses;
  final double profit;
  final int transactions;
  final Map<String, double> topProducts;
}

final reportSummaryProvider = FutureProvider.autoDispose
    .family<ReportSummary, ({String businessId, DateTime from, DateTime to})>(
        (ref, args) async {
  final sales = ref.watch(saleRepositoryProvider);
  final expenseRepo = ref.watch(expenseRepositoryProvider);

  final toExclusive = addDays(args.to, 1);
  final revenue =
      await sales.sumBetween(args.businessId, args.from, toExclusive);
  final exp =
      await expenseRepo.sumBetween(args.businessId, args.from, toExclusive);
  final top =
      await sales.topProductsByRevenue(args.businessId, args.from, toExclusive);
  final tx = await sales.countBetween(args.businessId, args.from, toExclusive);

  return ReportSummary(
    revenue: revenue,
    expenses: exp,
    profit: revenue - exp,
    transactions: tx,
    topProducts: top,
  );
});

/// Derived observations for the business, worst-first.
///
/// `autoDispose` like the rest: the rules read a lot of history, and holding
/// the result after the user leaves the screen would serve them a stale set
/// after they record the very sale that resolves one.
final insightsProvider = FutureProvider.autoDispose
    .family<List<Insight>, String>((ref, businessId) async {
  return ref.watch(insightsServiceProvider).generate(businessId);
});
