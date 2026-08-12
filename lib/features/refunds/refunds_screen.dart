import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import '../../util/ids.dart';

class RefundsScreen extends ConsumerWidget {
  const RefundsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(refundsProvider(businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Refunds')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay alive together, so the default hero tag collides.
        heroTag: 'fab_refunds',
        onPressed: () => context.push('/business/$businessId/refunds/new'),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Process refund'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(refundsProvider(businessId));
          await ref.read(refundsProvider(businessId).future);
        },
        child: async.when(
          loading: () => const RefreshableFill(child: LoadingView()),
          error: (e, _) => RefreshableFill(
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(refundsProvider(businessId)),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return RefreshableFill(
                child: EmptyState(
                  icon: Icons.replay_outlined,
                  title: 'No refunds yet',
                  message:
                      'Process a refund when a customer returns something. '
                      'Restocking puts the items back into inventory.',
                  actionLabel: 'Process refund',
                  onAction: () =>
                      context.push('/business/$businessId/refunds/new'),
                ),
              );
            }

            final total = rows.fold<double>(0, (sum, r) => sum + r.amount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
              children: [
                SelloraCard(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total refunded',
                                style: context.text.labelSmall),
                            Gap.h4,
                            Text(
                              formatPhp(total),
                              style: context.text.headlineSmall
                                  ?.copyWith(color: context.t.danger),
                            ),
                          ],
                        ),
                      ),
                      SelloraPill(
                        label:
                            '${rows.length} refund${rows.length == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                Gap.h16,
                ...rows.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: _RefundCard(refund: r),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.refund});

  final Refund refund;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return SelloraCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.dangerSoft,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(Icons.replay, size: 17, color: t.danger),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPhp(refund.amount),
                      style: context.text.titleSmall?.copyWith(color: t.danger),
                    ),
                    Text(formatTimestamp(refund.at),
                        style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (refund.note.isNotEmpty) ...[
            Gap.h8,
            Text(refund.note, style: context.text.bodyMedium),
          ],
          Gap.h8,
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            children: [
              if (refund.saleId != null)
                const SelloraPill(label: 'Linked to sale', icon: Icons.link),
              if (refund.restock)
                const SelloraPill(
                  label: 'Restocked',
                  tone: PillTone.success,
                  icon: Icons.inventory_2_outlined,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RefundFormScreen extends ConsumerStatefulWidget {
  const RefundFormScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<RefundFormScreen> createState() => _RefundFormScreenState();
}

class _RefundFormScreenState extends ConsumerState<RefundFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  String? _saleId;
  bool _restock = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Process refund')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
          children: [
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Refund amount',
                prefixText: '₱ ',
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            Gap.h12,
            salesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (sales) {
                // A sale deleted mid-form would otherwise trip the dropdown.
                final selected =
                    sales.any((s) => s.id == _saleId) ? _saleId : null;
                return DropdownButtonFormField<String?>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Original sale',
                    helperText: 'Required to restock the items.',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No linked sale'),
                    ),
                    ...sales.map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          '${formatPhp(s.total)} · ${formatTimestamp(s.createdAt)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() {
                    _saleId = v;
                    // Restock has nothing to act on without a sale.
                    if (v == null) _restock = false;
                  }),
                );
              },
            ),
            Gap.h12,
            SelloraCard(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _restock,
                onChanged: _saleId == null
                    ? null
                    : (v) => setState(() => _restock = v),
                title: Text(
                  'Restock items',
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _saleId == null
                      ? 'Pick the original sale first.'
                      : 'Puts every line from that sale back into inventory.',
                  style: context.text.bodySmall,
                ),
              ),
            ),
            Gap.h12,
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText:
                    'Optional — damaged, wrong item, customer changed mind',
              ),
            ),
            Gap.h24,
            FilledButton(
              onPressed: _saving ? null : _save,
              child:
                  _saving ? const ButtonSpinner() : const Text('Save refund'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_restock && _saleId == null) {
      showToast(context, 'Select a sale to restock, or turn restock off.',
          isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(refundRepositoryProvider);
      final refund = Refund(
        id: newLocalId('rfd'),
        businessId: widget.businessId,
        saleId: _saleId,
        amount: double.parse(_amount.text.trim()),
        note: _note.text.trim(),
        restock: _restock,
        at: DateTime.now(),
      );

      final lines = (_restock && _saleId != null)
          ? await repo.linesForSale(_saleId!)
          : null;

      await repo.processRefund(refund: refund, saleLinesIfRestock: lines);

      ref.invalidate(refundsProvider(widget.businessId));
      ref.invalidate(salesProvider(widget.businessId));
      ref.invalidate(productsProvider(widget.businessId));
      ref.invalidate(stockLedgerProvider(widget.businessId));
      ref.invalidate(dashboardStatsProvider(widget.businessId));

      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      showToast(context, 'Refund recorded');
      context.pop();
    } catch (e) {
      if (mounted) showToast(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
