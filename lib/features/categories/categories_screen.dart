import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import '../../util/ids.dart';

/// Manages the product categories of one business.
///
/// Deleting a category never deletes products: `products.category_id` is
/// ON DELETE SET NULL, so its products fall back to uncategorized.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider(businessId));
    final usage =
        ref.watch(categoryUsageProvider(businessId)).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay alive together, so the default hero tag collides.
        heroTag: 'fab_categories',
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add category'),
      ),
      body: categoriesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(categoriesProvider(businessId)),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return EmptyState(
              icon: Icons.sell_outlined,
              title: 'No categories yet',
              message:
                  'Categories group your products so the list and your reports '
                  'stay readable. Products without one still work fine.',
              actionLabel: 'Add category',
              onAction: () => _openEditor(context, ref),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 100),
            itemCount: categories.length,
            separatorBuilder: (_, __) => Gap.h8,
            itemBuilder: (context, i) {
              final category = categories[i];
              final count = usage[category.id] ?? 0;
              final t = context.t;

              return SelloraCard(
                padding:
                    const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.sm, Gap.sm),
                onTap: () => _openEditor(context, ref, existing: category),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.surfaceAlt,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child:
                          Icon(Icons.sell_outlined, size: 17, color: t.muted),
                    ),
                    Gap.w12,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.name,
                            style: context.text.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            count == 1 ? '1 product' : '$count products',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: t.muted),
                      onSelected: (action) => action == 'rename'
                          ? _openEditor(context, ref, existing: category)
                          : _confirmDelete(context, ref, category, count),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                          value: 'delete',
                          child:
                              Text('Delete', style: TextStyle(color: t.danger)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Category? existing,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CategoryNameDialog(businessId: businessId, existing: existing),
    );
    if (name == null || !context.mounted) return;

    try {
      final repo = ref.read(categoryRepositoryProvider);
      if (existing == null) {
        await repo.insert(Category(
          id: newLocalId('cat'),
          businessId: businessId,
          name: name,
          createdAt: DateTime.now(),
        ));
      } else {
        await repo.rename(id: existing.id, name: name);
      }
      _refresh(ref);
      if (context.mounted) {
        showToast(
            context, existing == null ? 'Category added' : 'Category renamed');
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Could not save: $e', isError: true);
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
    int productCount,
  ) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete category',
      message: productCount == 0
          ? 'Delete "${category.name}"?'
          : 'Delete "${category.name}"? Its $productCount '
              '${productCount == 1 ? 'product stays' : 'products stay'} but '
              '${productCount == 1 ? 'becomes' : 'become'} uncategorized.',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(categoryRepositoryProvider).delete(category.id);
      _refresh(ref);
      if (context.mounted) showToast(context, '${category.name} deleted');
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Could not delete: $e', isError: true);
      }
    }
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(categoriesProvider(businessId));
    ref.invalidate(categoryUsageProvider(businessId));
    // Product rows show their category name, and a delete just nulled some out.
    ref.invalidate(productsProvider(businessId));
  }
}

class _CategoryNameDialog extends ConsumerStatefulWidget {
  const _CategoryNameDialog({required this.businessId, this.existing});

  final String businessId;
  final Category? existing;

  @override
  ConsumerState<_CategoryNameDialog> createState() =>
      _CategoryNameDialogState();
}

class _CategoryNameDialogState extends ConsumerState<_CategoryNameDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Rename category' : 'New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: context.text.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Drinks',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            Gap.h12,
            Text(
              _error!,
              style: context.text.bodySmall?.copyWith(color: context.t.danger),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final clash = await ref.read(categoryRepositoryProvider).nameExists(
            businessId: widget.businessId,
            name: name,
            exceptId: widget.existing?.id,
          );
      if (!mounted) return;
      if (clash) {
        setState(() {
          _checking = false;
          _error = '"$name" already exists.';
        });
        return;
      }
      Navigator.of(context).pop(name);
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }
}
