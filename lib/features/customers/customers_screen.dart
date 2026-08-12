import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customersProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay alive together, so the default hero tag collides.
        heroTag: 'fab_customers',
        onPressed: () =>
            context.push('/business/${widget.businessId}/customers/new'),
        icon: const Icon(Icons.person_add_alt_outlined, size: 20),
        label: const Text('Add customer'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(customersProvider(widget.businessId));
          await ref.read(customersProvider(widget.businessId).future);
        },
        child: async.when(
          loading: () => const RefreshableFill(child: LoadingView()),
          error: (e, _) => RefreshableFill(
            child: ErrorView(
              error: e,
              onRetry: () =>
                  ref.invalidate(customersProvider(widget.businessId)),
            ),
          ),
          data: (customers) {
            if (customers.isEmpty) {
              return RefreshableFill(
                child: EmptyState(
                  icon: Icons.people_outline,
                  title: 'No customers yet',
                  message:
                      'Add your first customer to link sales to them. Everything stays on this device.',
                  actionLabel: 'Add customer',
                  onAction: () => context
                      .push('/business/${widget.businessId}/customers/new'),
                ),
              );
            }

            final query = _search.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? customers
                : customers
                    .where((c) =>
                        c.name.toLowerCase().contains(query) ||
                        c.phone.toLowerCase().contains(query) ||
                        c.email.toLowerCase().contains(query))
                    .toList(growable: false);

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
              children: [
                SelloraSearchField(
                  controller: _search,
                  hintText: 'Search customers...',
                  onChanged: (_) => setState(() {}),
                ),
                Gap.h8,
                Text(
                  '${customers.length} customer${customers.length == 1 ? '' : 's'}',
                  style: context.text.labelSmall,
                ),
                Gap.h12,
                if (filtered.isEmpty)
                  const EmptyState(
                    icon: Icons.search_off,
                    title: 'No results found',
                    message: 'Try a different name, phone, or email.',
                    compact: true,
                  )
                else
                  ...filtered.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: Gap.sm),
                      child: _CustomerCard(
                        customer: c,
                        onEdit: () => context.push(
                          '/business/${widget.businessId}/customers/edit/${c.id}',
                        ),
                        onDelete: () => _delete(c),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(Customer customer) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete customer',
      message:
          'Delete ${customer.name}? Their past sales stay in your records but '
          'will no longer be linked to a customer.',
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(customerRepositoryProvider).delete(customer.id);
      ref.invalidate(customersProvider(widget.businessId));
      ref.invalidate(salesProvider(widget.businessId));
      if (mounted) showToast(context, '${customer.name} deleted');
    } catch (e) {
      if (mounted) showToast(context, 'Could not delete: $e', isError: true);
    }
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final contact = [customer.phone, customer.email]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');

    return SelloraCard(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
      onTap: onEdit,
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: t.accentSoft,
            child: Text(
              _initials(customer.name),
              style: context.text.labelMedium?.copyWith(color: t.accent),
            ),
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (contact.isNotEmpty)
                  Text(
                    contact,
                    style: context.text.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: t.muted),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: t.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}
