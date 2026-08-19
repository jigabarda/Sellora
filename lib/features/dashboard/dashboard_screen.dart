import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import '../insights/insights_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider(businessId));
    final sales = ref.watch(salesProvider(businessId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(businessProvider(businessId));
        ref.invalidate(dashboardStatsProvider(businessId));
        ref.invalidate(salesProvider(businessId));
        ref.invalidate(insightsProvider(businessId));
        await ref.read(dashboardStatsProvider(businessId).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
        children: [
          _QuickEntryBar(businessId: businessId),
          Gap.h12,
          stats.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: LoadingView(),
            ),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(dashboardStatsProvider(businessId)),
            ),
            data: (s) => _StatsGrid(stats: s, businessId: businessId),
          ),
          Gap.h16,
          _InsightsCard(businessId: businessId),
          sales.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => Column(
              children: [
                _ProductPerformanceCard(sales: list),
                Gap.h12,
                _RecentSalesCard(businessId: businessId, sales: list),
                Gap.h12,
                _QuickActionsCard(businessId: businessId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens Quick Entry. Deliberately shaped like a search field rather than a
/// button: it invites typing, and typing is the fast path this exists to offer.
class _QuickEntryBar extends StatelessWidget {
  const _QuickEntryBar({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return SelloraCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.md,
      ),
      color: t.surfaceAlt,
      onTap: () => context.push('/business/$businessId/quick'),
      child: Row(
        children: [
          Icon(Icons.bolt_outlined, size: 20, color: t.accent),
          Gap.w12,
          Expanded(
            child: Text(
              'Log a sale or expense…',
              style: context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.businessId});

  final DashboardStats stats;
  final String businessId;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Column(
      children: [
        // Today's takings is the number owners open the app for, so it gets
        // the full-width treatment and the only saturated surface on the
        // screen. Everything below stays quiet so this reads first.
        SelloraCard(
          color: t.accent,
          border: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "Today's sales",
                    style: context.text.labelSmall?.copyWith(
                      // Not full-strength onAccent: this is the caption above
                      // the figure, and it should sit behind it.
                      color: t.onAccent.withValues(alpha: 0.75),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      // Tinted from the foreground rather than a fixed white,
                      // so the chip stays visible on a light accent too.
                      color: t.onAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '${stats.transactions} all-time',
                      style: context.text.labelSmall?.copyWith(
                        color: t.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
              Gap.h8,
              // Counts up on arrival. The figure lands a moment after the
              // card does, which draws the eye to the one number the owner
              // opened the app to see. Short enough that it never delays
              // reading it.
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: stats.todaySales),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  formatPhp(value),
                  style: context.text.displaySmall?.copyWith(
                    color: t.onAccent,
                    // Locked to tabular figures so the digits do not jitter
                    // sideways while the number is still climbing.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Gap.h4,
              Text(
                'This week: ${formatPhp(stats.weekSales)}',
                style: context.text.bodyMedium?.copyWith(
                  color: t.onAccent.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        Gap.h12,
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Active products',
                value: '${stats.activeProducts}',
                icon: Icons.inventory_2_outlined,
                tone: t.accent,
                onTap: () => context.go('/business/$businessId/products'),
              ),
            ),
            Gap.w12,
            Expanded(
              child: StatTile(
                label: 'Low stock',
                value: '${stats.lowStockCount}',
                // Icon and colour move together. A falling-trend glyph in
                // green says two opposite things at once, so the healthy
                // state gets its own mark rather than just a recolour.
                icon: stats.lowStockCount > 0
                    ? Icons.trending_down
                    : Icons.check_circle_outline,
                // Only turns amber when there is actually something to act
                // on; a permanent warning colour stops meaning anything.
                tone: stats.lowStockCount > 0 ? t.warning : t.success,
                onTap: () => context.push('/business/$businessId/inventory'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The two most urgent insights, inline on the dashboard.
///
/// Deliberately not behind a tab: a warning the owner has to go looking for is
/// one they will find after it mattered. Renders nothing at all when there is
/// nothing to say — an empty "Insights" heading would be worse than absence.
class _InsightsCard extends ConsumerWidget {
  const _InsightsCard({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights =
        ref.watch(insightsProvider(businessId)).valueOrNull ?? const [];
    if (insights.isEmpty) return const SizedBox.shrink();

    final top = insights.take(2).toList();
    final remaining = insights.length - top.length;

    return Column(
      children: [
        for (final insight in top) ...[
          InsightCard(insight: insight),
          Gap.h8,
        ],
        if (remaining > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/business/$businessId/insights'),
              child: Text(
                '$remaining more insight${remaining == 1 ? '' : 's'}',
              ),
            ),
          ),
        Gap.h8,
      ],
    );
  }
}

class _ProductPerformanceCard extends StatelessWidget {
  const _ProductPerformanceCard({required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final rows = _performanceRows(sales).take(4).toList();
    final maxRevenue = rows.isEmpty ? 0.0 : rows.first.revenue;

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: Icons.bar_chart,
            title: 'Product performance',
            subtitle: 'Revenue by product, all time',
          ),
          Gap.h16,
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: Center(
                child: Text('No product sales yet',
                    style: context.text.bodyMedium),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Gap.h12,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Gap.w8,
                  Text(formatPhp(rows[i].revenue),
                      style: context.text.titleSmall),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value:
                            maxRevenue == 0 ? 0 : rows[i].revenue / maxRevenue,
                        backgroundColor: t.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(t.accent),
                      ),
                    ),
                  ),
                  Gap.w8,
                  Text(
                    '${rows[i].quantity} sold',
                    style: context.text.labelSmall,
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static List<_PerformanceRow> _performanceRows(List<Sale> sales) {
    final map = <String, _PerformanceRow>{};
    for (final sale in sales) {
      for (final line in sale.lines) {
        final current = map[line.name] ?? _PerformanceRow(line.name, 0, 0);
        map[line.name] = _PerformanceRow(
          line.name,
          current.quantity + line.qty,
          // `line.total` rather than qty * price: it carries the rental
          // days, which are 1 for anything sold outright.
          current.revenue + line.total,
        );
      }
    }
    final rows = map.values.toList();
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }
}

class _RecentSalesCard extends ConsumerWidget {
  const _RecentSalesCard({required this.businessId, required this.sales});

  final String businessId;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final recent = sales.take(4).toList();
    // Resolve real customer names rather than labelling everything walk-in.
    final customerNames = {
      for (final c
          in ref.watch(customersProvider(businessId)).valueOrNull ?? const [])
        c.id: c.name,
    };

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: Icons.receipt_long_outlined,
            title: 'Recent sales',
            subtitle: 'Latest transactions',
            trailing: TextButton(
              onPressed: () => context.go('/business/$businessId/sales'),
              child: const Text('View all'),
            ),
          ),
          Gap.h12,
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: Center(
                child: Text('No sales yet', style: context.text.bodyMedium),
              ),
            )
          else
            for (final sale in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.md,
                  ),
                  decoration: BoxDecoration(
                    color: t.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerNames[sale.customerId] ?? 'Walk-in',
                              style: context.text.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              formatTimestamp(sale.createdAt),
                              style: context.text.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Text(formatPhp(sale.total),
                          style: context.text.titleSmall),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context) {
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: Icons.bolt_outlined,
            title: 'Quick actions',
            subtitle: 'Common tasks',
          ),
          Gap.h16,
          FilledButton.icon(
            onPressed: () => context.push('/business/$businessId/sales/new'),
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Record a sale'),
          ),
          Gap.h8,
          OutlinedButton.icon(
            onPressed: () => context.push('/business/$businessId/products/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a product'),
          ),
          Gap.h8,
          OutlinedButton.icon(
            onPressed: () => context.push('/business/$businessId/expenses/new'),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Record an expense'),
          ),
        ],
      ),
    );
  }
}

class _PerformanceRow {
  const _PerformanceRow(this.name, this.quantity, this.revenue);

  final String name;
  final int quantity;
  final double revenue;
}
