import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _CartLine {
  _CartLine({required this.product, required this.qty});

  final Product product;
  int qty;

  double get subtotal => qty * product.price;

  /// Null means no ceiling: the product does not track stock.
  int? get max => product.trackStock ? product.stock : null;
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final List<_CartLine> _cart = [];
  String? _customerId;
  bool _saving = false;

  double get _total => _cart.fold(0.0, (sum, l) => sum + l.subtotal);
  int get _itemCount => _cart.fold(0, (sum, l) => sum + l.qty);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final productsAsync = ref.watch(productsProvider(widget.businessId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          if (_cart.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _clearCart,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(productsProvider(widget.businessId)),
        ),
        data: (products) => Column(
          children: [
            Expanded(
              child: _cart.isEmpty
                  ? EmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Cart is empty',
                      message: 'Add products to build this sale. Stock is only '
                          'deducted once you save.',
                      actionLabel: 'Add product',
                      onAction: () => _pickProduct(products),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.lg, Gap.md, Gap.lg, Gap.md),
                      children: [
                        _customerPicker(),
                        Gap.h16,
                        Padding(
                          padding: const EdgeInsets.only(
                              left: Gap.xs, bottom: Gap.sm),
                          child: Text(
                            'Cart · $_itemCount item${_itemCount == 1 ? '' : 's'}',
                            style: context.text.labelSmall,
                          ),
                        ),
                        ..._cart.asMap().entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: Gap.sm),
                                child: _CartCard(
                                  line: e.value,
                                  onDecrement: () => _changeQty(e.value, -1),
                                  onIncrement: () => _changeQty(e.value, 1),
                                  onRemove: () =>
                                      setState(() => _cart.removeAt(e.key)),
                                ),
                              ),
                            ),
                        Gap.h8,
                        OutlinedButton.icon(
                          onPressed: () => _pickProduct(products),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add another product'),
                        ),
                      ],
                    ),
            ),
            // Checkout bar stays pinned so the total is always visible.
            Container(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(top: BorderSide(color: t.line)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('Total', style: context.text.bodyMedium),
                          const Spacer(),
                          Text(formatPhp(_total),
                              style: context.text.headlineSmall),
                        ],
                      ),
                      Gap.h12,
                      FilledButton(
                        onPressed: (_saving || _cart.isEmpty) ? null : _submit,
                        child: _saving
                            ? const ButtonSpinner()
                            : Text('Record sale · ${formatPhp(_total)}'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerPicker() {
    final customersAsync = ref.watch(customersProvider(widget.businessId));
    return customersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (customers) {
        // A customer deleted mid-sale would otherwise trip the dropdown.
        final selected =
            customers.any((c) => c.id == _customerId) ? _customerId : null;
        return DropdownButtonFormField<String?>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Customer'),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Walk-in')),
            ...customers.map(
              (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
            ),
          ],
          onChanged: (v) => setState(() => _customerId = v),
        );
      },
    );
  }

  void _changeQty(_CartLine line, int delta) {
    final next = line.qty + delta;
    if (next < 1) return;
    if (line.max != null && next > line.max!) return;
    HapticFeedback.selectionClick();
    setState(() => line.qty = next);
  }

  Future<void> _clearCart() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear cart',
      message: 'Remove all $_itemCount items from this sale?',
      confirmLabel: 'Clear',
    );
    if (confirmed && mounted) setState(_cart.clear);
  }

  Future<void> _pickProduct(List<Product> products) async {
    // Untracked products have no inventory, so `stock > 0` must not gate them
    // — their stock column sits at 0 forever.
    final sellable = products
        .where((p) => p.active && (!p.trackStock || p.stock > 0))
        .toList(growable: false);

    if (sellable.isEmpty) {
      showToast(
        context,
        products.isEmpty
            ? 'Add a product first.'
            : 'Nothing is in stock right now.',
        isError: true,
      );
      return;
    }

    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductPickerSheet(products: sellable),
    );
    if (picked == null || !mounted) return;

    HapticFeedback.selectionClick();
    setState(() {
      final existing = _cart.indexWhere((c) => c.product.id == picked.id);
      if (existing >= 0) {
        final line = _cart[existing];
        if (line.max == null || line.qty < line.max!) line.qty++;
      } else {
        _cart.add(_CartLine(product: picked, qty: 1));
      }
    });
  }

  Future<void> _submit() async {
    if (_cart.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(saleRepositoryProvider).recordSale(
            businessId: widget.businessId,
            customerId: _customerId,
            lines: _cart
                .map((c) => (
                      productId: c.product.id,
                      name: c.product.name,
                      qty: c.qty,
                      unitPrice: c.product.price,
                    ))
                .toList(growable: false),
          );

      ref.invalidate(salesProvider(widget.businessId));
      ref.invalidate(productsProvider(widget.businessId));
      ref.invalidate(dashboardStatsProvider(widget.businessId));
      ref.invalidate(stockLedgerProvider(widget.businessId));

      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      showToast(context, 'Sale recorded · ${formatPhp(_total)}');
      context.pop();
    } catch (e) {
      if (mounted) {
        showToast(context, 'Could not record sale: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _CartCard extends StatelessWidget {
  const _CartCard({
    required this.line,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  final _CartLine line;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final atMax = line.max != null && line.qty >= line.max!;

    return SelloraCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${formatPhp(line.product.price)} each · ${formatPhp(line.subtotal)}',
                  style: context.text.bodySmall,
                ),
                if (atMax)
                  Text(
                    'All ${line.max} ${line.product.unit} in cart',
                    style: context.text.labelSmall?.copyWith(color: t.warning),
                  ),
              ],
            ),
          ),
          Gap.w8,
          Container(
            decoration: BoxDecoration(
              color: t.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepButton(
                  icon: line.qty > 1 ? Icons.remove : Icons.delete_outline,
                  onPressed: line.qty > 1 ? onDecrement : onRemove,
                  danger: line.qty == 1,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${line.qty}',
                    textAlign: TextAlign.center,
                    style: context.text.titleSmall,
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  onPressed: atMax ? null : onIncrement,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = onPressed == null
        ? t.faint
        : danger
            ? t.danger
            : t.ink;

    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products});

  final List<Product> products;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.products
        : widget.products
            .where((p) =>
                p.name.toLowerCase().contains(query) ||
                p.sku.toLowerCase().contains(query))
            .toList(growable: false);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Add product', style: context.text.titleMedium),
                Gap.h12,
                SelloraSearchField(
                  controller: _search,
                  hintText: 'Search products...',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'No results',
                    message: 'Try a different name or SKU.',
                    compact: true,
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xl),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Gap.h8,
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      return SelloraCard(
                        padding: const EdgeInsets.all(Gap.md),
                        onTap: () => Navigator.pop(context, p),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: context.text.bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  SelloraPill(
                                    label: p.trackStock
                                        ? '${p.stock} ${p.unit} left'
                                        : 'Unlimited',
                                    tone: p.trackStock
                                        ? PillTone.neutral
                                        : PillTone.accent,
                                  ),
                                ],
                              ),
                            ),
                            Gap.w8,
                            Text(formatPhp(p.price),
                                style: context.text.titleSmall),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
