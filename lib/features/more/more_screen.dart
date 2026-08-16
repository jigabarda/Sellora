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
        _MoreItem(
            'Customers',
            Icons.people_outline,
            '/business/$businessId/customers',
            'Contacts and purchase history',
            _MoreTone.accent),
        _MoreItem(
            'Categories',
            Icons.sell_outlined,
            '/business/$businessId/categories',
            'Group products for easier browsing',
            _MoreTone.accent),
        _MoreItem(
            'Inventory',
            Icons.warehouse_outlined,
            '/business/$businessId/inventory',
            'Stock levels and movement history',
            _MoreTone.accent),
      ]),
      _MoreGroup('Money', [
        _MoreItem(
            'Insights',
            Icons.lightbulb_outline,
            '/business/$businessId/insights',
            'What needs attention right now',
            _MoreTone.money),
        _MoreItem(
            'Expenses',
            Icons.receipt_long_outlined,
            '/business/$businessId/expenses',
            'What the business spends',
            _MoreTone.money),
        _MoreItem(
            'Refunds',
            Icons.replay_outlined,
            '/business/$businessId/refunds',
            'Returns and money given back',
            _MoreTone.money),
        _MoreItem(
            'Reports',
            Icons.bar_chart_outlined,
            '/business/$businessId/reports',
            'Revenue, profit, and top products',
            _MoreTone.money),
      ]),
      _MoreGroup('Account', [
        _MoreItem(
            'Settings',
            Icons.settings_outlined,
            '/business/$businessId/settings',
            'Profile, business, backup, danger zone',
            _MoreTone.quiet),
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
      leading: IconTile(
        icon: item.icon,
        tone: _moreToneColour(context, item.tone),
        size: 34,
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
  const _MoreItem(this.title, this.icon, this.path, this.subtitle, this.tone);

  final String title;
  final IconData icon;
  final String path;
  final String subtitle;

  /// Which hue the row's icon tile takes. An enum rather than a Color so the
  /// list above can stay `const` while the colour still resolves per theme.
  final _MoreTone tone;
}

/// Grouped by what the destination is about, not by taste: stock and catalogue
/// tools share the brand colour, anything touching money is green, and the
/// account group is deliberately quiet so Settings never competes with the
/// operational rows above it.
enum _MoreTone { accent, money, quiet }

Color _moreToneColour(BuildContext context, _MoreTone tone) {
  final t = context.t;
  return switch (tone) {
    _MoreTone.accent => t.accent,
    _MoreTone.money => t.success,
    _MoreTone.quiet => t.muted,
  };
}
