import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(salesProvider(businessId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(salesProvider(businessId));
        await ref.read(salesProvider(businessId).future);
      },
      child: async.when(
        loading: () => const RefreshableFill(child: LoadingView()),
        error: (e, _) => RefreshableFill(
          child: ErrorView(
            error: e,
            onRetry: () => ref.invalidate(salesProvider(businessId)),
          ),
        ),
        data: (sales) {
          if (sales.isEmpty) {
            return RefreshableFill(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No sales yet',
                message:
                    'Record your first sale to get started. It works offline '
                    'and stock updates the moment you save.',
                actionLabel: 'Record a sale',
                onAction: () => context.push('/business/$businessId/sales/new'),
              ),
            );
          }

          final grouped = _groupByDay(sales);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
            itemCount: grouped.length,
            itemBuilder: (context, i) {
              final group = grouped[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (i > 0) Gap.h16,
                  Padding(
                    padding:
                        const EdgeInsets.only(bottom: Gap.sm, left: Gap.xs),
                    child: Row(
                      children: [
                        Text(group.label, style: context.text.labelMedium),
                        const Spacer(),
                        Text(
                          formatPhp(group.total),
                          style: context.text.labelMedium
                              ?.copyWith(color: context.t.ink),
                        ),
                      ],
                    ),
                  ),
                  ...group.sales.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: _SaleCard(sale: s),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Sales read far better bucketed by day with a running daily total than as
  /// one flat list of timestamps.
  static List<_DayGroup> _groupByDay(List<Sale> sales) {
    final groups = <String, _DayGroup>{};
    for (final sale in sales) {
      final day = startOfTodayLocal(sale.createdAt);
      final key = day.toIso8601String();
      final group = groups.putIfAbsent(
        key,
        () => _DayGroup(label: _dayLabel(day), sales: [], total: 0),
      );
      group.sales.add(sale);
      group.total += sale.total;
    }
    return groups.values.toList(growable: false);
  }

  static String _dayLabel(DateTime day) {
    final today = startOfTodayLocal();
    if (day == today) return 'Today';
    if (day == addDays(today, -1)) return 'Yesterday';
    return formatDay(day);
  }
}

class _DayGroup {
  _DayGroup({required this.label, required this.sales, required this.total});

  final String label;
  final List<Sale> sales;
  double total;
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final itemCount = sale.lines.fold<int>(0, (sum, l) => sum + l.qty);

    return SelloraCard(
      padding: EdgeInsets.zero,
      child: Theme(
        // The default divider on an expansion tile fights the card border.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          // Money in is `success`, the mirror of the `danger` used for
          // expenses and refunds. A sales list and an expenses list should be
          // tellable apart at a glance.
          leading: IconTile(icon: Icons.receipt_long_outlined, tone: t.success),
          title: Text(
            formatPhp(sale.total),
            style: context.text.titleSmall,
          ),
          subtitle: Text(
            '$itemCount item${itemCount == 1 ? '' : 's'} · ${formatTimestamp(sale.createdAt)}',
            style: context.text.bodySmall,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
          children: [
            Container(height: 1, color: t.line),
            Gap.h8,
            ...sale.lines.map(
              (l) => DetailRow(
                label: '${l.name} × ${l.qty}',
                value: formatPhp(l.qty * l.unitPrice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesScaffold extends ConsumerWidget {
  const SalesScaffold({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SalesScreen(businessId: businessId),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Counter mode sits above the form, smaller and quieter. It is the
          // faster way to sell and will be the one reached for all day, but it
          // is also the newer one — leading with the familiar button and
          // letting this be discovered costs nothing, and demoting the form
          // before anyone has tried the counter would cost trust.
          FloatingActionButton.small(
            heroTag: 'fab_counter',
            tooltip: 'Counter mode',
            onPressed: () =>
                context.push('/business/$businessId/sales/counter'),
            child: const Icon(Icons.grid_view_rounded, size: 20),
          ),
          Gap.h12,
          FloatingActionButton.extended(
            // Shell branches stay alive together, so the default hero tag
            // collides.
            heroTag: 'fab_sales',
            onPressed: () => context.push('/business/$businessId/sales/new'),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('New sale'),
          ),
        ],
      ),
    );
  }
}
