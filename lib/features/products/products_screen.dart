import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';

const _lowStockThreshold = 5;

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productsProvider(widget.businessId));
    final categoryNames = {
      for (final c
          in ref.watch(categoriesProvider(widget.businessId)).valueOrNull ??
              const [])
        c.id: c.name,
    };

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(productsProvider(widget.businessId));
        await ref.read(productsProvider(widget.businessId).future);
      },
      child: async.when(
        loading: () => const RefreshableFill(child: LoadingView()),
        error: (e, _) => RefreshableFill(
          child: ErrorView(
            error: e,
            onRetry: () => ref.invalidate(productsProvider(widget.businessId)),
          ),
        ),
        data: (products) {
          if (products.isEmpty) {
            return RefreshableFill(
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'No products yet',
                message:
                    'Add your first product to start selling. Stock is tracked '
                    'locally so it keeps working offline.',
                actionLabel: 'Add product',
                onAction: () =>
                    context.push('/business/${widget.businessId}/products/new'),
              ),
            );
          }

          final query = _search.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? products
              : products
                  .where((p) =>
                      p.name.toLowerCase().contains(query) ||
                      p.sku.toLowerCase().contains(query) ||
                      p.description.toLowerCase().contains(query))
                  .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
            children: [
              SelloraSearchField(
                controller: _search,
                hintText: 'Search products...',
                onChanged: (_) => setState(() {}),
              ),
              Gap.h8,
              Row(
                children: [
                  Text(
                    '${products.length} product${products.length == 1 ? '' : 's'}',
                    style: context.text.labelSmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context
                        .push('/business/${widget.businessId}/categories'),
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text('Categories'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                      minimumSize: const Size(0, 32),
                      textStyle: context.text.labelMedium,
                    ),
                  ),
                ],
              ),
              Gap.h8,
              if (filtered.isEmpty)
                const EmptyState(
                  icon: Icons.search_off,
                  title: 'No results found',
                  message: 'Try a different name, SKU, or description.',
                  compact: true,
                )
              else
                ...filtered.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: _ProductCard(
                      product: p,
                      categoryName: categoryNames[p.categoryId],
                      onTap: () => context.push(
                        '/business/${widget.businessId}/products/edit/${p.id}',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.categoryName,
    required this.onTap,
  });

  final Product product;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lowStock = product.trackStock && product.stock <= _lowStockThreshold;

    return SelloraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gives an alphabetical list a colour to scan by. Inactive
              // products drop to muted so the row visibly steps back without
              // losing the "Inactive" pill that actually states it.
              InitialsTile(
                label: product.name,
                tone: product.active ? null : context.t.faint,
              ),
              Gap.w12,
              Expanded(
                child: Text(
                  product.name,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Gap.w8,
              Text(formatPhp(product.price), style: context.text.titleSmall),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              product.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall,
            ),
          ],
          Gap.h8,
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!product.trackStock)
                const SelloraPill(label: 'Unlimited', tone: PillTone.accent)
              else
                SelloraPill(
                  label: '${product.stock} ${product.unit}',
                  tone: lowStock ? PillTone.warning : PillTone.neutral,
                  icon: lowStock ? Icons.trending_down : null,
                ),
              if (categoryName != null) SelloraPill(label: categoryName!),
              if (!product.active)
                const SelloraPill(label: 'Inactive', tone: PillTone.danger),
              if (product.sku.isNotEmpty)
                Text('SKU ${product.sku}', style: context.text.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class ProductsScaffold extends ConsumerWidget {
  const ProductsScaffold({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ProductsScreen(businessId: businessId),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay alive together, so the default hero tag collides.
        heroTag: 'fab_products',
        onPressed: () => context.push('/business/$businessId/products/new'),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add product'),
      ),
    );
  }
}
