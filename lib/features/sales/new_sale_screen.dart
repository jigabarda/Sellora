import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../data/quick_entry/quick_command.dart';
import '../../data/sales/sale_cart.dart';
import '../../providers.dart';
import 'discount_sheet.dart';
import 'rental_period_sheet.dart';
import 'quantity_sheet.dart';

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key, required this.businessId, this.prefill});

  final String businessId;

  /// Seeded by Quick Entry. Lands in the cart exactly as a tapped product
  /// would, so there is no second path into `recordSale`.
  final RecordSaleCommand? prefill;

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _cart = SaleCart();
  String? _customerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill == null) return;
    // The cart clamps for the same reason the picker does: a tracked product
    // cannot be sold beyond what is on the shelf, and a parsed quantity is a
    // guess.
    _cart.add(prefill.product, qty: prefill.quantity);
    _customerId = prefill.customer?.id;
  }

  /// Taken off the sale, in pesos. Clamped down if the cart shrinks below it,
  /// so a discount entered against a bigger cart can never exceed what is
  /// left.
  double _discount = 0;

  double get _subtotal => _cart.total;
  double get _discountApplied => _discount > _subtotal ? _subtotal : _discount;
  double get _total => _subtotal - _discountApplied;
  int get _itemCount => _cart.itemCount;

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
                        ..._cart.lines.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: Gap.sm),
                            child: _CartCard(
                              line: line,
                              onDecrement: () => _changeQty(line, -1),
                              onIncrement: () => _changeQty(line, 1),
                              onRemove: () =>
                                  setState(() => _cart.remove(line)),
                              onEditQty: () => _editQty(line),
                              onEditDays: () => _editDays(line),
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
                      if (_discountApplied > 0) ...[
                        Row(
                          children: [
                            Text('Subtotal', style: context.text.bodySmall),
                            const Spacer(),
                            Text(formatPhp(_subtotal),
                                style: context.text.bodySmall),
                          ],
                        ),
                        Row(
                          children: [
                            Text('Discount',
                                style: context.text.bodySmall
                                    ?.copyWith(color: t.success)),
                            const Spacer(),
                            Text('- ${formatPhp(_discountApplied)}',
                                style: context.text.bodySmall
                                    ?.copyWith(color: t.success)),
                          ],
                        ),
                        Gap.h4,
                      ],
                      Row(
                        children: [
                          Text('Total', style: context.text.bodyMedium),
                          const Spacer(),
                          Text(formatPhp(_total),
                              style: context.text.headlineSmall),
                        ],
                      ),
                      Gap.h4,
                      // Left of the total rather than buried in a menu: a
                      // discount is agreed while the customer is standing
                      // there, not remembered afterwards.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed:
                              (_saving || _cart.isEmpty) ? null : _editDiscount,
                          icon: const Icon(Icons.sell_outlined, size: 18),
                          label: Text(_discountApplied > 0
                              ? 'Change discount'
                              : 'Add discount'),
                        ),
                      ),
                      Gap.h4,
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

  Future<void> _editQty(CartLine line) async {
    final chosen = await askQuantity(
      context,
      productName: line.product.name,
      current: line.qty,
      max: line.max,
    );
    if (chosen == null || !mounted) return;
    setState(() => _cart.setQuantity(line, chosen));
  }

  Future<void> _editDiscount() async {
    final chosen = await askDiscount(
      context,
      subtotal: _subtotal,
      current: _discountApplied,
    );
    if (chosen == null || !mounted) return;
    setState(() => _discount = chosen);
  }

  Future<void> _editDays(CartLine line) async {
    final from = line.startsAt;
    final to = line.endsAt;
    final chosen = await askRentalPeriod(
      context,
      productName: line.product.name,
      current: from != null && to != null
          ? DateTimeRange(start: from, end: to)
          : null,
    );
    if (chosen == null || !mounted) return;
    setState(() => _cart.setPeriod(line, chosen.start, chosen.end));
  }

  void _changeQty(CartLine line, int delta) {
    final next = line.qty + delta;
    if (next < 1) return;
    if (line.max != null && next > line.max!) return;
    HapticFeedback.selectionClick();
    setState(() => _cart.setQuantity(line, next));
  }

  Future<void> _clearCart() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear cart',
      message: 'Remove all $_itemCount items from this sale?',
      confirmLabel: 'Clear',
    );
    // The discount goes with it: it was agreed against these items, and
    // leaving it behind would silently apply it to whatever comes next.
    if (confirmed && mounted) {
      setState(() {
        _cart.clear();
        _discount = 0;
      });
    }
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
    setState(() => _cart.add(picked));
  }

  Future<void> _submit() async {
    if (_cart.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(saleRepositoryProvider).recordSale(
            businessId: widget.businessId,
            customerId: _customerId,
            lines: _cart.toSaleLines(),
            discount: _discountApplied,
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
    required this.onEditQty,
    required this.onEditDays,
  });

  final CartLine line;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;
  final VoidCallback onEditQty;
  final VoidCallback onEditDays;

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
                  line.isRental
                      ? '${formatPhp(line.product.price)} a day · '
                          '${line.days} ${line.days == 1 ? 'day' : 'days'} · '
                          '${formatPhp(line.subtotal)}'
                      : '${formatPhp(line.product.price)} each · '
                          '${formatPhp(line.subtotal)}',
                  style: context.text.bodySmall,
                ),
                if (line.isRental) ...[
                  Gap.h4,
                  // Only rentals get this. Putting a day count on a sold line
                  // would invite someone to change it, and a sold thing is not
                  // out for a period.
                  InkWell(
                    onTap: onEditDays,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Gap.sm, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_outlined,
                              size: 14, color: t.accent),
                          Gap.w4,
                          Text(
                            line.startsAt == null
                                ? 'Set the dates'
                                : '${formatDay(line.startsAt!)} → '
                                    '${formatDay(line.endsAt!)}',
                            style: context.text.labelSmall
                                ?.copyWith(color: t.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
                // Tappable: the stepper is fine for two or three and useless
                // for fifty, which is an ordinary order here.
                InkWell(
                  onTap: onEditQty,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm, vertical: 4),
                    child: Text(
                      '${line.qty}',
                      textAlign: TextAlign.center,
                      style: context.text.titleSmall,
                    ),
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
