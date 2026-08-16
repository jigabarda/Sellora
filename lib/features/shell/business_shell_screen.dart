import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../providers.dart';

/// Branch order must match `StatefulShellRoute.indexedStack` in `router.dart`.
const _branches = <({IconData icon, IconData active, String label})>[
  (
    icon: Icons.dashboard_outlined,
    active: Icons.dashboard,
    label: 'Dashboard',
  ),
  (
    icon: Icons.inventory_2_outlined,
    active: Icons.inventory_2,
    label: 'Products',
  ),
  (
    icon: Icons.point_of_sale_outlined,
    active: Icons.point_of_sale,
    label: 'Sales',
  ),
  (
    icon: Icons.grid_view_outlined,
    active: Icons.grid_view,
    label: 'More',
  ),
];

class BusinessShellScreen extends ConsumerWidget {
  const BusinessShellScreen({
    super.key,
    required this.businessId,
    required this.navigationShell,
  });

  final String businessId;
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final business = ref.watch(businessProvider(businessId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Open menu',
            icon: const Icon(Icons.menu, size: 22),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              business?.name ?? 'Sellora',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall,
            ),
            Text(
              _branches[navigationShell.currentIndex].label,
              style: context.text.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch business',
            icon: const Icon(Icons.swap_horiz, size: 21),
            onPressed: () => context.go('/'),
          ),
          Gap.w4,
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.line),
        ),
      ),
      drawer: _BusinessDrawer(
        businessId: businessId,
        selectedIndex: navigationShell.currentIndex,
        onBranchSelected: _goBranch,
      ),
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          top: false,
          // Sized by its content rather than a fixed height: the label's line
          // box varies with the platform font and the user's text scale, and
          // a hardcoded height overflows the moment it grows.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < _branches.length; i++)
                  Expanded(
                    child: _NavItem(
                      branch: _branches[i],
                      selected: navigationShell.currentIndex == i,
                      onTap: () => _goBranch(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goBranch(int index) {
    HapticFeedback.selectionClick();
    navigationShell.goBranch(
      index,
      // Tapping the active tab again pops that branch back to its root, which
      // is what every native app does.
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.branch,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData active, String label}) branch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = selected ? t.accent : t.faint;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              // The selected pill is the brand tint, so the active tab is
              // obvious from colour alone rather than only from weight.
              color: selected ? t.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Icon(
              selected ? branch.active : branch.icon,
              size: 21,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            branch.label,
            style: context.text.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessDrawer extends ConsumerWidget {
  const _BusinessDrawer({
    required this.businessId,
    required this.selectedIndex,
    required this.onBranchSelected,
  });

  final String businessId;
  final int selectedIndex;
  final ValueChanged<int> onBranchSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final business = ref.watch(businessProvider(businessId)).valueOrNull;

    void go(String path) {
      Navigator.of(context).pop();
      context.push(path);
    }

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.8,
      backgroundColor: t.canvas,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
              child: SelloraWordmark(size: 22),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
              child: SelloraCard(
                padding: const EdgeInsets.all(Gap.md),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go('/');
                },
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.accentSoft,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Icon(Icons.storefront_outlined,
                          size: 17, color: t.accent),
                    ),
                    Gap.w12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            business?.name ?? 'Business',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            business?.type ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 17, color: t.faint),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _DrawerLabel('Menu'),
                  for (var i = 0; i < _branches.length; i++)
                    _DrawerItem(
                      icon: _branches[i].icon,
                      title: _branches[i].label,
                      active: selectedIndex == i,
                      onTap: () {
                        Navigator.of(context).pop();
                        onBranchSelected(i);
                      },
                    ),
                  Gap.h16,
                  const _DrawerLabel('Operations'),
                  _DrawerItem(
                    icon: Icons.groups_outlined,
                    title: 'Customers',
                    onTap: () => go('/business/$businessId/customers'),
                  ),
                  _DrawerItem(
                    icon: Icons.sell_outlined,
                    title: 'Categories',
                    onTap: () => go('/business/$businessId/categories'),
                  ),
                  _DrawerItem(
                    icon: Icons.warehouse_outlined,
                    title: 'Inventory',
                    onTap: () => go('/business/$businessId/inventory'),
                  ),
                  Gap.h16,
                  const _DrawerLabel('Money'),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    title: 'Expenses',
                    onTap: () => go('/business/$businessId/expenses'),
                  ),
                  _DrawerItem(
                    icon: Icons.replay_outlined,
                    title: 'Refunds',
                    onTap: () => go('/business/$businessId/refunds'),
                  ),
                  _DrawerItem(
                    icon: Icons.bar_chart_outlined,
                    title: 'Reports',
                    onTap: () => go('/business/$businessId/reports'),
                  ),
                  Gap.h16,
                  const _DrawerLabel('Account'),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: () => go('/business/$businessId/settings'),
                  ),
                  _DrawerItem(
                    icon: Icons.save_alt_outlined,
                    title: 'Backup & restore',
                    onTap: () => go('/backup'),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: t.line),
            _DrawerItem(
              icon: Icons.logout,
              title: 'Sign out',
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).logout();
                ref.invalidate(businessesProvider);
                if (context.mounted) context.go('/welcome');
              },
            ),
            Gap.h8,
          ],
        ),
      ),
    );
  }
}

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.xs),
      child: Text(label, style: context.text.labelSmall),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 1),
      child: Material(
        color: active ? t.surfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 19, color: active ? t.ink : t.muted),
                Gap.w12,
                Expanded(
                  child: Text(
                    title,
                    style: context.text.bodyLarge?.copyWith(
                      color: t.ink,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
