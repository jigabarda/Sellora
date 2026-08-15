import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../providers.dart';

/// Presets cover the ranges a shop owner actually asks for; the custom picker
/// is there for everything else.
enum _RangePreset { today, week, month, custom }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _RangePreset _preset = _RangePreset.week;
  late DateTime _from = startOfTodayLocal().subtract(const Duration(days: 6));
  late DateTime _to = startOfTodayLocal();

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(
      reportSummaryProvider(
        (businessId: widget.businessId, from: _from, to: _to),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(reportSummaryProvider(
            (businessId: widget.businessId, from: _from, to: _to),
          ));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
          children: [
            _rangePicker(),
            Gap.h16,
            summary.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: LoadingView(),
              ),
              error: (e, _) => ErrorView(error: e),
              data: (r) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Revenue',
                          value: formatPhp(r.revenue),
                          icon: Icons.trending_up,
                          tone: context.t.success,
                          compact: true,
                        ),
                      ),
                      Gap.w12,
                      Expanded(
                        child: StatTile(
                          label: 'Expenses',
                          value: formatPhp(r.expenses),
                          icon: Icons.trending_down,
                          tone: context.t.danger,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                  Gap.h12,
                  SelloraCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.profit >= 0 ? 'Profit' : 'Loss',
                                    style: context.text.labelSmall,
                                  ),
                                  Gap.h4,
                                  Text(
                                    formatPhp(r.profit.abs()),
                                    style: context.text.displaySmall?.copyWith(
                                      color: r.profit >= 0
                                          ? context.t.success
                                          : context.t.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SelloraPill(
                              label:
                                  '${r.transactions} sale${r.transactions == 1 ? '' : 's'}',
                            ),
                          ],
                        ),
                        if (r.revenue > 0) ...[
                          Gap.h16,
                          _MarginBar(
                            revenue: r.revenue,
                            expenses: r.expenses,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Gap.h16,
                  Padding(
                    padding:
                        const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
                    child: Text('Top products', style: context.text.labelSmall),
                  ),
                  if (r.topProducts.isEmpty)
                    const EmptyState(
                      icon: Icons.bar_chart_outlined,
                      title: 'No sales in this period',
                      message:
                          'Pick a wider date range, or record a sale first.',
                      compact: true,
                    )
                  else
                    _TopProducts(products: r.topProducts),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangePicker() {
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Gap.sm,
            children: [
              _presetChip('Today', _RangePreset.today),
              _presetChip('7 days', _RangePreset.week),
              _presetChip('30 days', _RangePreset.month),
              _presetChip('Custom', _RangePreset.custom),
            ],
          ),
          Gap.h12,
          Row(
            children: [
              Icon(Icons.date_range, size: 16, color: context.t.muted),
              Gap.w8,
              Expanded(
                child: Text(
                  '${formatDay(_from)} — ${formatDay(_to)}',
                  style: context.text.bodyMedium,
                ),
              ),
              if (_preset == _RangePreset.custom)
                TextButton(
                  onPressed: _pickCustomRange,
                  child: const Text('Change'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, _RangePreset preset) {
    final selected = _preset == preset;
    final t = context.t;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: context.text.labelMedium?.copyWith(
        color: selected ? t.onAccent : t.muted,
      ),
      backgroundColor: t.surfaceAlt,
      selectedColor: t.accent,
      side: BorderSide(color: selected ? t.accent : t.line),
      onSelected: (_) => _applyPreset(preset),
    );
  }

  void _applyPreset(_RangePreset preset) {
    final today = startOfTodayLocal();
    setState(() {
      _preset = preset;
      switch (preset) {
        case _RangePreset.today:
          _from = today;
          _to = today;
        case _RangePreset.week:
          _from = addDays(today, -6);
          _to = today;
        case _RangePreset.month:
          _from = addDays(today, -29);
          _to = today;
        case _RangePreset.custom:
          break;
      }
    });
    if (preset == _RangePreset.custom) _pickCustomRange();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: startOfTodayLocal(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _preset = _RangePreset.custom;
        _from = startOfTodayLocal(picked.start);
        _to = startOfTodayLocal(picked.end);
      });
    }
  }
}

/// Proportion of revenue eaten by expenses — the one "chart" that earns its
/// space on a phone.
class _MarginBar extends StatelessWidget {
  const _MarginBar({required this.revenue, required this.expenses});

  final double revenue;
  final double expenses;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ratio = (expenses / revenue).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                Expanded(
                  flex: ((1 - ratio) * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: t.success),
                ),
                Expanded(
                  flex: (ratio * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: t.danger),
                ),
              ],
            ),
          ),
        ),
        Gap.h8,
        Text(
          '${((1 - ratio) * 100).toStringAsFixed(0)}% of revenue kept',
          style: context.text.labelSmall,
        ),
      ],
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.products});

  final Map<String, double> products;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final entries = products.entries.toList();
    final max = entries.first.value;

    return SelloraCard(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Gap.h12,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entries[i].key,
                        style: context.text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Gap.w8,
                    Text(formatPhp(entries[i].value),
                        style: context.text.titleSmall),
                  ],
                ),
                Gap.h4,
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: max == 0 ? 0 : entries[i].value / max,
                    minHeight: 5,
                    backgroundColor: t.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(t.accent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
