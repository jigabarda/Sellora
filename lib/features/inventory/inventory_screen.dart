import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';

const _lowStockThreshold = 5;

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final products = ref.watch(productsProvider(widget.businessId));
    final ledger = ref.watch(stockLedgerProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: t.ink,
          unselectedLabelColor: t.faint,
          indicatorColor: t.accent,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: t.line,
          labelStyle: context.text.labelLarge,
          unselectedLabelStyle: context.text.labelLarge,
          tabs: const [
            Tab(text: 'Stock levels'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          products.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () =>
                  ref.invalidate(productsProvider(widget.businessId)),
            ),
            data: _stockLevels,
          ),
          ledger.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () =>
                  ref.invalidate(stockLedgerProvider(widget.businessId)),
            ),
            data: _history,
          ),
        ],
      ),
    );
  }

  Widget _stockLevels(List<Product> all) {
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nothing to track yet',
        message: 'Add products first and their stock levels will show up here.',
      );
    }

    // Untracked products have no inventory to report on.
    final tracked = all.where((p) => p.trackStock).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    if (tracked.isEmpty) {
      return const EmptyState(
        icon: Icons.all_inclusive,
        title: 'No products track stock',
        message:
            'Every product is set to unlimited. Turn on "Track stock" for a '
            'product to see it here.',
      );
    }

    final low = tracked.where((p) => p.stock <= _lowStockThreshold).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Tracked',
                value: '${tracked.length}',
                icon: Icons.inventory_2_outlined,
              ),
            ),
            Gap.w12,
            Expanded(
              child: _StatTile(
                label: 'Low stock',
                value: '$low',
                icon: Icons.trending_down,
                tone: low > 0 ? PillTone.warning : PillTone.neutral,
              ),
            ),
          ],
        ),
        Gap.h16,
        ...tracked.map((p) {
          final isLow = p.stock <= _lowStockThreshold;
          return Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: SelloraCard(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: context.text.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          p.sku.isEmpty ? 'No SKU' : 'SKU ${p.sku}',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Gap.w12,
                  if (isLow) ...[
                    const SelloraPill(label: 'Low', tone: PillTone.warning),
                    Gap.w8,
                  ],
                  Text(
                    '${p.stock}',
                    style: context.text.titleMedium?.copyWith(
                      color: isLow ? context.t.warning : context.t.ink,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(p.unit, style: context.text.labelSmall),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _history(List<StockLedgerEntry> rows) {
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No stock movements yet',
        message:
            'Sales, refunds, and manual adjustments all write a line here so '
            'you can trace every change.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
      itemCount: rows.length,
      separatorBuilder: (_, __) => Gap.h8,
      itemBuilder: (context, i) {
        final e = rows[i];
        final positive = e.delta >= 0;
        final tone = positive ? context.t.success : context.t.danger;

        return SelloraCard(
          padding:
              const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      (positive ? context.t.successSoft : context.t.dangerSoft),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  positive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: tone,
                ),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _reasonLabel(e.reason),
                      style: context.text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      e.note.isEmpty
                          ? formatTimestamp(e.at)
                          : '${e.note} · ${formatTimestamp(e.at)}',
                      style: context.text.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Gap.w8,
              Text(
                '${positive ? '+' : ''}${e.delta}',
                style: context.text.titleSmall?.copyWith(color: tone),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _reasonLabel(String reason) => switch (reason) {
        'sale' => 'Sale',
        'initial' => 'Initial stock',
        'adjustment' => 'Manual adjustment',
        'refund' => 'Refund restock',
        _ => reason,
      };
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = PillTone.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = tone == PillTone.warning ? t.warning : t.muted;

    return SelloraCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          Gap.h8,
          Text(value, style: context.text.headlineSmall),
          Text(label, style: context.text.labelSmall),
        ],
      ),
    );
  }
}
