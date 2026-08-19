import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/auth/auth_controller.dart';
import 'data/quick_entry/quick_command.dart';
import 'core/sellora_ui.dart';
import 'features/auth/landing_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/backup/backup_screen.dart';
import 'features/business/new_business_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/expenses/expenses_screen.dart';
import 'features/home/home_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/notebook_capture/notebook_capture_screen.dart';
import 'features/notebook_capture/ocr_report_screen.dart';
import 'features/quick_entry/quick_entry_screen.dart';
import 'features/more/more_screen.dart';
import 'features/products/product_form_screen.dart';
import 'features/products/products_screen.dart';
import 'features/refunds/refunds_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/sales/new_sale_screen.dart';
import 'features/sales/sales_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/business_shell_screen.dart';
import 'providers.dart';

/// Used to present full-screen flows above the bottom navigation shell.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class _GoRouterAuthRefresh extends ChangeNotifier {
  _GoRouterAuthRefresh(Ref ref) {
    _sub = ref.listen<AuthState>(
      authControllerProvider,
      (_, __) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _GoRouterAuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  final loggedInInitially = ref.read(authControllerProvider).userId != null;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    initialLocation: loggedInInitially ? '/' : '/welcome',
    // Without this a mistyped or stale deep link surfaces a raw GoRouter
    // exception page to the user.
    errorBuilder: (context, state) =>
        _RouteNotFound(location: state.uri.toString()),
    redirect: (context, state) {
      final loggedIn = ref.read(authControllerProvider).userId != null;
      final loc = state.matchedLocation;
      final authRoute =
          loc == '/welcome' || loc == '/login' || loc == '/register';
      if (!loggedIn && !authRoute) return '/welcome';
      if (loggedIn && authRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/business/new',
        name: 'business_new',
        builder: (context, state) => const NewBusinessScreen(),
      ),
      // Account-level, not business-level: one backup covers every business.
      GoRoute(
        path: '/backup',
        name: 'backup',
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: '/business/:businessId',
        redirect: (context, state) {
          final id = state.pathParameters['businessId']!;
          if (state.uri.path == '/business/$id') {
            return '/business/$id/dashboard';
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              final id = state.pathParameters['businessId']!;
              return BusinessShellScreen(
                businessId: id,
                navigationShell: navigationShell,
              );
            },
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'dashboard',
                    name: 'business_dashboard',
                    builder: (context, state) {
                      final id = state.pathParameters['businessId']!;
                      return DashboardScreen(businessId: id);
                    },
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'products',
                    name: 'business_products',
                    builder: (context, state) {
                      final id = state.pathParameters['businessId']!;
                      return ProductsScaffold(businessId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: rootNavigatorKey,
                        name: 'business_product_new',
                        builder: (context, state) {
                          final id = state.pathParameters['businessId']!;
                          return ProductFormScreen(businessId: id);
                        },
                      ),
                      GoRoute(
                        path: 'edit/:productId',
                        parentNavigatorKey: rootNavigatorKey,
                        name: 'business_product_edit',
                        builder: (context, state) {
                          final id = state.pathParameters['businessId']!;
                          final pid = state.pathParameters['productId']!;
                          return ProductFormScreen(
                              businessId: id, productId: pid);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'sales',
                    name: 'business_sales',
                    builder: (context, state) {
                      final id = state.pathParameters['businessId']!;
                      return SalesScaffold(businessId: id);
                    },
                    routes: [
                      GoRoute(
                        path: 'new',
                        parentNavigatorKey: rootNavigatorKey,
                        name: 'business_sale_new',
                        builder: (context, state) {
                          final id = state.pathParameters['businessId']!;
                          final prefill = state.extra;
                          return NewSaleScreen(
                            businessId: id,
                            prefill:
                                prefill is RecordSaleCommand ? prefill : null,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: 'more',
                    name: 'business_more',
                    builder: (context, state) {
                      final id = state.pathParameters['businessId']!;
                      return MoreScreen(businessId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: 'customers',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_customers',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return CustomersScreen(businessId: id);
            },
            routes: [
              GoRoute(
                path: 'new',
                parentNavigatorKey: rootNavigatorKey,
                name: 'business_customer_new',
                builder: (context, state) {
                  final id = state.pathParameters['businessId']!;
                  return CustomerFormScreen(businessId: id);
                },
              ),
              GoRoute(
                path: 'edit/:customerId',
                parentNavigatorKey: rootNavigatorKey,
                name: 'business_customer_edit',
                builder: (context, state) {
                  final id = state.pathParameters['businessId']!;
                  final cid = state.pathParameters['customerId']!;
                  return CustomerFormScreen(businessId: id, customerId: cid);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'categories',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_categories',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return CategoriesScreen(businessId: id);
            },
          ),
          GoRoute(
            path: 'inventory',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_inventory',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return InventoryScreen(businessId: id);
            },
          ),
          GoRoute(
            path: 'expenses',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_expenses',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return ExpensesScreen(businessId: id);
            },
            routes: [
              GoRoute(
                path: 'new',
                parentNavigatorKey: rootNavigatorKey,
                name: 'business_expense_new',
                builder: (context, state) {
                  final id = state.pathParameters['businessId']!;
                  final prefill = state.extra;
                  return ExpenseFormScreen(
                    businessId: id,
                    prefill: prefill is AddExpenseCommand ? prefill : null,
                  );
                },
              ),
              GoRoute(
                path: 'edit/:expenseId',
                parentNavigatorKey: rootNavigatorKey,
                name: 'business_expense_edit',
                builder: (context, state) {
                  final id = state.pathParameters['businessId']!;
                  final eid = state.pathParameters['expenseId']!;
                  return ExpenseFormScreen(businessId: id, expenseId: eid);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'refunds',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_refunds',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return RefundsScreen(businessId: id);
            },
            routes: [
              GoRoute(
                path: 'new',
                parentNavigatorKey: rootNavigatorKey,
                name: 'business_refund_new',
                builder: (context, state) {
                  final id = state.pathParameters['businessId']!;
                  return RefundFormScreen(businessId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'quick',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_quick_entry',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return QuickEntryScreen(businessId: id);
            },
          ),
          GoRoute(
            path: 'scan',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_notebook_capture',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return NotebookCaptureScreen(businessId: id);
            },
          ),
          // Debug builds only. `ocrReportEnabled` is `kDebugMode`, a const
          // false in release, so this route and the button that reaches it are
          // tree shaken out of shipped builds.
          if (ocrReportEnabled)
            GoRoute(
              path: 'scan/diagnose',
              parentNavigatorKey: rootNavigatorKey,
              name: 'business_ocr_report',
              builder: (context, state) {
                final id = state.pathParameters['businessId']!;
                return OcrReportScreen(businessId: id);
              },
            ),
          GoRoute(
            path: 'insights',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_insights',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return InsightsScreen(businessId: id);
            },
          ),
          GoRoute(
            path: 'reports',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_reports',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return ReportsScreen(businessId: id);
            },
          ),
          GoRoute(
            path: 'settings',
            parentNavigatorKey: rootNavigatorKey,
            name: 'business_settings',
            builder: (context, state) {
              final id = state.pathParameters['businessId']!;
              return SettingsScreen(businessId: id);
            },
          ),
        ],
      ),
    ],
  );
});

class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: 'This page does not exist',
        message: 'Nothing is registered at $location.',
        actionLabel: 'Go home',
        onAction: () => context.go('/'),
      ),
    );
  }
}
