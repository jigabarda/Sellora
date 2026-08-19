import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/export/device_downloads.dart';
import '../../providers.dart';

const _xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

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
  bool _exporting = false;

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
                  Gap.h16,
                  _RevenueTrend(
                    businessId: widget.businessId,
                    from: _from,
                    to: _to,
                  ),
                  Gap.h16,
                  Padding(
                    padding:
                        const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
                    child: Text('Export as Excel',
                        style: context.text.labelSmall),
                  ),
                  FilledButton.icon(
                    onPressed: _exporting ? null : _saveToDevice,
                    icon: _exporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                    label: Text(
                      _exporting ? 'Preparing…' : 'Save to device',
                    ),
                  ),
                  Gap.h8,
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : _share,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Send a copy'),
                  ),
                  Gap.h8,
                  Text(
                    'Summary, every sale, products and expenses for this '
                    'period. Saving puts it in Downloads; sending hands it to '
                    'an app you pick. It never leaves the phone on its own.',
                    style: context.text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Puts the spreadsheet in Downloads, where the owner can find it again.
  ///
  /// Falls through to the share sheet on Android 9 and older, where saving to
  /// a public folder would mean asking for a storage permission this app does
  /// not have and is not going to acquire for an export.
  Future<void> _saveToDevice() async {
    setState(() => _exporting = true);
    try {
      final report = await ref.read(reportExportServiceProvider).buildReport(
            businessId: widget.businessId,
            from: _from,
            to: _to,
            generatedAt: DateTime.now(),
          );

      final saved = await ref.read(deviceDownloadsProvider).save(
            fileName: report.fileName,
            bytes: report.bytes,
            mimeType: _xlsxMimeType,
          );

      if (!mounted) return;
      showToast(context, 'Saved to Downloads as $saved');
    } on DownloadsUnsupported {
      if (!mounted) return;
      showToast(context, 'This phone cannot save straight to Downloads — '
          'choose where to put it instead.');
      setState(() => _exporting = false);
      await _share();
      return;
    } catch (e) {
      if (mounted) showToast(context, 'Could not save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _share() async {
    setState(() => _exporting = true);
    File? file;
    try {
      file = await ref.read(reportExportServiceProvider).writeReportFile(
            businessId: widget.businessId,
            from: _from,
            to: _to,
            generatedAt: DateTime.now(),
          );

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: _xlsxMimeType,
            ),
          ],
          subject: 'Sellora report ${formatDay(_from)} to ${formatDay(_to)}',
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, 'Sharing failed: $e', isError: true);
    } finally {
      // The share sheet copies what it needs; the cache copy is disposable.
      try {
        await file?.delete();
      } on FileSystemException {
        // Nothing to clean up — the cache is evictable anyway.
      }
      if (mounted) setState(() => _exporting = false);
    }
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

/// How the trend is grouped. A phone is about 330dp wide, so the grain has to
/// follow the range: 365 daily bars is not a chart, it is a texture.
enum _Grain { day, week, month }

extension on _Grain {
  String get label => switch (this) {
        _Grain.day => 'by day',
        _Grain.week => 'by week',
        _Grain.month => 'by month',
      };
}

/// Revenue over the reported period.
///
/// The summary above answers "how much"; this answers the question an owner
/// actually asks next, which is "is it going up or down".
class _RevenueTrend extends ConsumerWidget {
  const _RevenueTrend({
    required this.businessId,
    required this.from,
    required this.to,
  });

  final String businessId;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byDay = ref.watch(
      revenueByDayProvider((businessId: businessId, from: from, to: to)),
    );

    return byDay.when(
      loading: () => const SelloraCard(
        child: SizedBox(height: 140, child: LoadingView()),
      ),
      // The trend is a bonus on a screen whose numbers already loaded; failing
      // it loudly would be louder than it is worth.
      error: (_, __) => const SizedBox.shrink(),
      data: (revenue) => _chart(context, revenue),
    );
  }

  Widget _chart(BuildContext context, Map<DateTime, double> revenue) {
    final t = context.t;
    final grain = _grainFor(from, to);
    final buckets = _bucketed(revenue, from, to, grain);
    final peak = buckets.fold<double>(0, (m, b) => math.max(m, b.value));

    if (buckets.isEmpty || peak <= 0) return const SizedBox.shrink();

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Revenue ${grain.label}',
                    style: context.text.labelSmall),
              ),
              Text('peak ${formatPhp(peak)}',
                  style: context.text.bodySmall?.copyWith(color: t.muted)),
            ],
          ),
          Gap.h12,
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < buckets.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    child: _Bar(
                      // Against the peak, not the total: the shape of the
                      // period is the point, and scaling to the sum would
                      // flatten every bar into the same sliver.
                      fraction: buckets[i].value / peak,
                      colour: t.accent,
                      empty: t.surfaceAlt,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Gap.h8,
          Row(
            children: [
              Text(formatDay(buckets.first.start),
                  style: context.text.bodySmall?.copyWith(color: t.muted)),
              const Spacer(),
              Text(formatDay(buckets.last.start),
                  style: context.text.bodySmall?.copyWith(color: t.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.colour,
    required this.empty,
  });

  final double fraction;
  final Color colour;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A day with sales must never render as nothing, or the chart says the
        // shop was shut when it was not.
        final height =
            fraction <= 0 ? 2.0 : math.max(3.0, box.maxHeight * fraction);
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: height,
              decoration: BoxDecoration(
                color: fraction <= 0 ? empty : colour,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        );
      },
    );
  }
}

_Grain _grainFor(DateTime from, DateTime to) {
  final days = to.difference(from).inDays + 1;
  if (days <= 31) return _Grain.day;
  if (days <= 182) return _Grain.week;
  return _Grain.month;
}

/// Every bucket in the range, including the empty ones.
///
/// Days with no sales have to appear, or a quiet week would silently compress
/// into a busy-looking chart and the gap — the thing worth noticing — vanishes.
List<({DateTime start, double value})> _bucketed(
  Map<DateTime, double> revenue,
  DateTime from,
  DateTime to,
  _Grain grain,
) {
  final out = <({DateTime start, double value})>[];
  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);

  DateTime cursor = switch (grain) {
    _Grain.day => first,
    _Grain.week => first,
    _Grain.month => DateTime(first.year, first.month),
  };

  while (!cursor.isAfter(last)) {
    final next = switch (grain) {
      _Grain.day => DateTime(cursor.year, cursor.month, cursor.day + 1),
      _Grain.week => DateTime(cursor.year, cursor.month, cursor.day + 7),
      _Grain.month => DateTime(cursor.year, cursor.month + 1),
    };

    var total = 0.0;
    for (final entry in revenue.entries) {
      if (!entry.key.isBefore(cursor) && entry.key.isBefore(next)) {
        total += entry.value;
      }
    }
    out.add((start: cursor, value: total));
    cursor = next;
  }
  return out;
}
