import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import 'quantity_sheet.dart';

/// What is out with customers, and the way to take it back.
///
/// Without this screen the rental half of the app is a lie: stock leaves the
/// shelf and never returns to it, and after a few weekends the shop's own
/// records say it owns nothing. Renting and returning are one feature with two
/// ends, and this is the second end.
///
/// The list is derived from the sale lines themselves — anything whose returned
/// count is short of what went out — rather than from a status anyone has to
/// remember to set. A row disappears when the numbers say it should, not when
/// someone ticks it off.
class RentalsOutScreen extends ConsumerWidget {
  const RentalsOutScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rentals = ref.watch(outstandingRentalsProvider(businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Out on rent')),
      body: rentals.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.assignment_turned_in_outlined,
              title: 'Nothing is out',
              message: 'Everything you rent out shows here until it comes '
                  'back, so you can see what is still with a customer.',
            );
          }

          final now = DateTime.now();
          final overdue = list.where((r) => r.isOverdue(now)).length;

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(outstandingRentalsProvider(businessId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
              children: [
                Text(
                  overdue == 0
                      ? '${list.length} still out'
                      : '${list.length} still out · $overdue past due',
                  style: context.text.bodyMedium?.copyWith(
                    color: overdue == 0 ? context.t.muted : context.t.danger,
                  ),
                ),
                Gap.h12,
                for (final rental in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: _RentalCard(
                      rental: rental,
                      now: now,
                      onReturn: () => _takeBack(context, ref, rental),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _takeBack(
    BuildContext context,
    WidgetRef ref,
    OutstandingRental rental,
  ) async {
    final qty = await askQuantity(
      context,
      productName: rental.productName,
      current: rental.outstanding,
      max: rental.outstanding,
      title: 'How many came back?',
    );
    if (qty == null || !context.mounted) return;

    try {
      await ref.read(saleRepositoryProvider).recordRentalReturn(
            businessId: businessId,
            lineId: rental.lineId,
            qty: qty,
          );

      ref.invalidate(outstandingRentalsProvider(businessId));
      ref.invalidate(productsProvider(businessId));
      ref.invalidate(dashboardStatsProvider(businessId));
      ref.invalidate(insightsProvider(businessId));

      if (!context.mounted) return;
      showToast(context, 'Took back $qty ${rental.productName}');
    } on StateError catch (e) {
      if (context.mounted) showToast(context, e.message, isError: true);
    }
  }
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({
    required this.rental,
    required this.now,
    required this.onReturn,
  });

  final OutstandingRental rental;
  final DateTime now;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final late = rental.isOverdue(now);
    final partly = rental.returnedQty > 0;

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rental.outstanding} × ${rental.productName}',
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Gap.w8,
              SelloraPill(
                label: late ? 'Past due' : 'Out',
                tone: late ? PillTone.danger : PillTone.neutral,
              ),
            ],
          ),
          Gap.h4,
          Text(
            // Whose it is comes first: chasing it up starts with a name.
            '${rental.customerName ?? 'Walk-in'} · '
            '${rental.days} ${rental.days == 1 ? 'day' : 'days'} from '
            '${formatDay(rental.rentedAt)}',
            style: context.text.bodySmall,
          ),
          Text(
            late
                ? 'Was due ${formatDay(rental.dueAt)}'
                : 'Due ${formatDay(rental.dueAt)}',
            style: context.text.bodySmall
                ?.copyWith(color: late ? t.danger : t.muted),
          ),
          if (partly)
            Text(
              '${rental.returnedQty} of ${rental.qty} already back',
              style: context.text.bodySmall?.copyWith(color: t.success),
            ),
          Gap.h12,
          Row(
            children: [
              Text(
                formatPhp(rental.qty * rental.unitPrice * rental.days),
                style: context.text.bodyMedium?.copyWith(color: t.muted),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: onReturn,
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Take back'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
