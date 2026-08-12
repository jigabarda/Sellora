import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context) {
    final groups = <_MoreGroup>[
      _MoreGroup('Operations', [
        _MoreItem('Customers', Icons.people_outline,
            '/business/$businessId/customers', 'Contacts and purchase history'),
        _MoreItem(
            'Categories',
            Icons.sell_outlined,
            '/business/$businessId/categories',
            'Group products for easier browsing'),
        _MoreItem(
            'Inventory',
            Icons.warehouse_outlined,
            '/business/$businessId/inventory',
            'Stock levels and movement history'),
      ]),
      _MoreGroup('Money', [
        _MoreItem('Expenses', Icons.receipt_long_outlined,
            '/business/$businessId/expenses', 'What the business spends'),
        _MoreItem('Refunds', Icons.replay_outlined,
            '/business/$businessId/refunds', 'Returns and money given back'),
        _MoreItem(
            'Reports',
            Icons.bar_chart_outlined,
            '/business/$businessId/reports',
            'Revenue, profit, and top products'),
      ]),
      _MoreGroup('Account', [
        _MoreItem(
            'Settings',
            Icons.settings_outlined,
            '/business/$businessId/settings',
            'Profile, business, backup, danger zone'),
      ]),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
      children: [
        Text('More tools', style: context.text.headlineSmall),
        const SizedBox(height: 2),
        Text(
          'Everything here runs fully offline on this device.',
          style: context.text.bodyMedium,
        ),
        Gap.h24,
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, bottom: Gap.sm),
            child: Text(group.title, style: context.text.labelSmall),
          ),
          SelloraCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 60),
                      child: Container(height: 1, color: context.t.line),
                    ),
                  _MoreTile(item: group.items[i]),
                ],
              ],
            ),
          ),
          Gap.h24,
        ],
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.item});

  final _MoreItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListTile(
      onTap: () => context.push(item.path),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(item.icon, size: 17, color: t.ink),
      ),
      title: Text(
        item.title,
        style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(item.subtitle, style: context.text.bodySmall),
      trailing: Icon(Icons.chevron_right, size: 20, color: t.faint),
    );
  }
}

class _MoreGroup {
  const _MoreGroup(this.title, this.items);

  final String title;
  final List<_MoreItem> items;
}

class _MoreItem {
  const _MoreItem(this.title, this.icon, this.path, this.subtitle);

  final String title;
  final IconData icon;
  final String path;
  final String subtitle;
}
