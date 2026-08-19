import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/repositories/business_repository.dart';
import '../../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(businessesProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: Gap.lg,
        title: const SelloraLockup(size: 20, shadow: false),
        actions: [
          IconButton(
            tooltip: 'Backup & restore',
            icon: const Icon(Icons.save_alt_outlined, size: 21),
            onPressed: () => context.push('/backup'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              ref.invalidate(businessesProvider);
              if (context.mounted) context.go('/welcome');
            },
          ),
          Gap.w4,
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(businessesProvider),
        ),
        data: (businesses) {
          if (businesses.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Welcome to Sellora',
              message:
                  "You haven't created a business yet. Set one up to start "
                  'tracking sales, inventory, and expenses — all on this device.',
              actionLabel: 'Create your first business',
              onAction: () => context.push('/business/new'),
            );
          }
          return _BusinessList(
              businesses: businesses, greetingName: user?.name);
        },
      ),
    );
  }
}

class _BusinessList extends ConsumerWidget {
  const _BusinessList({required this.businesses, this.greetingName});

  final List<Business> businesses;
  final String? greetingName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = greetingName?.trim().split(' ').first;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(businessesProvider);
        await ref.read(businessesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 40),
        children: [
          Text(
            firstName == null ? 'Your businesses' : 'Hello, $firstName',
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 2),
          Text(
            businesses.length == 1
                ? 'Tap your business to open its dashboard.'
                : 'Pick a business to open its dashboard.',
            style: context.text.bodyMedium,
          ),
          Gap.h24,
          for (final business in businesses)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: _BusinessCard(business: business),
            ),
          Gap.h8,
          OutlinedButton.icon(
            onPressed: () => context.push('/business/new'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add another business'),
          ),
        ],
      ),
    );
  }
}

class _BusinessCard extends ConsumerWidget {
  const _BusinessCard({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final stats = ref.watch(dashboardStatsProvider(business.id)).valueOrNull;

    return SelloraCard(
      onTap: () => context.go('/business/${business.id}/dashboard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child:
                    Icon(Icons.storefront_outlined, size: 20, color: t.accent),
              ),
              Gap.w12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.name,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(business.type, style: context.text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: t.faint),
            ],
          ),
          // Stats load per business; showing the card immediately and filling
          // these in beats blocking the whole list on a query.
          if (stats != null) ...[
            Gap.h16,
            Container(height: 1, color: t.line),
            Gap.h12,
            Row(
              children: [
                _MiniStat(label: 'Products', value: '${stats.activeProducts}'),
                _MiniStat(label: 'Sales', value: '${stats.transactions}'),
                if (stats.lowStockCount > 0)
                  _MiniStat(
                    label: 'Low stock',
                    value: '${stats.lowStockCount}',
                    tone: t.warning,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.text.titleMedium?.copyWith(color: tone),
          ),
          Text(label, style: context.text.labelSmall),
        ],
      ),
    );
  }
}
