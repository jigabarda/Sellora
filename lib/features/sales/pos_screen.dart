import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../data/sales/sale_cart.dart';
import '../../providers.dart';
import 'quantity_sheet.dart';

/// Counter mode: the products on screen, one tap each.
///
/// The sale form is the right shape for a considered sale — pick a customer,
/// build a few lines, check it. It is the wrong shape for a queue. Three taps
/// and a bottom sheet per item is fine once and painful twenty times, and the
/// owner standing at a counter has a queue, not a form.
///
/// So this is the same sale, laid out for speed: every sellable product is
/// already on screen, a tap adds one, and the total is always visible. Nothing
/// here is a new way to record a sale — it builds the same [SaleCart] the form
/// builds and hands it to the same `recordSale`. The rules about merging rows
/// and running out of stock live in the cart precisely so these two screens
/// cannot answer them differently.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _cart = SaleCart();
  final _search = TextEditingController();
  String? _customerId;
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider(widget.businessId)).valueOrNull ?? const [];
    final customers =
        ref.watch(customersProvider(widget.businessId)).valueOrNull ?? const [];

    // Untracked products have no inventory, so `stock > 0` must not gate them
    // — their stock column sits at 0 forever.
    final sellable = products
        .where((p) => p.active && (!p.trackStock || p.stock > 0))
        .toList(growable: false);

    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? sellable
        : sellable
            .where((p) => p.name.toLowerCase().contains(query))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter'),
        actions: [
          if (_cart.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : () => setState(_cart.clear),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: sellable.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing to sell yet',
              message: 'Add a product, or restock one that has run out, and it '
                  'will appear here.',
            )
          : Column(
              children: [
                if (sellable.length > 8)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.lg, Gap.md, Gap.lg, Gap.sm),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Find a product',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                    ),
                  ),
                Expanded(
                  child: shown.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: 'No product matches',
                          message: 'Try a shorter word.',
                          compact: true,
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              Gap.lg, Gap.sm, Gap.lg, Gap.lg),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            // Two columns on a phone, more on a tablet, without
                            // hard-coding either.
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: Gap.sm,
                            crossAxisSpacing: Gap.sm,
                            // Wider than tall: the tile only has to carry a
                            // name, a price and a badge, and a squarer one left
                            // a hole in the middle.
                            // Sized to the contents — a name of up to two
                            // lines, a price, and nothing else. Found by
                            // testing: 2.05 clips a wrapped name.
                            childAspectRatio: 1.80,
                          ),
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final product = shown[i];
                            return _ProductTile(
                              product: product,
                              inCart: _cart.quantityOf(product.id),
                              onTap: () => _add(product),
                              onLongPress: () => _addExact(product),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: sellable.isEmpty
          ? null
          : _CheckoutBar(
              cart: _cart,
              customers: customers,
              customerId: _customerId,
              saving: _saving,
              onCustomerChanged: (id) => setState(() => _customerId = id),
              onReview: _cart.isEmpty ? null : _review,
              onRecord: _cart.isEmpty || _saving ? null : _record,
            ),
    );
  }

  void _add(Product product) {
    final added = _cart.add(product);
    if (!added) {
      showToast(context, 'No ${product.name} left in stock', isError: true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Long press: type the quantity rather than tapping for it.
  Future<void> _addExact(Product product) async {
    final already = _cart.quantityOf(product.id);
    final chosen = await askQuantity(
      context,
      productName: product.name,
      current: already > 0 ? already : 1,
      max: product.trackStock ? product.stock : null,
    );
    if (chosen == null || !mounted) return;

    setState(() {
      final line = _cart.lines.where((l) => l.product.id == product.id);
      if (line.isEmpty) {
        _cart.add(product, qty: chosen);
      } else {
        // The sheet asks for the total for this product, not an increment —
        // it opened showing what is already there.
        _cart.setQuantity(line.first, chosen);
      }
    });
  }

  /// The cart, for checking and correcting before it is recorded.
  Future<void> _review() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CartSheet(
        cart: _cart,
        onChanged: () => setState(() {}),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _record() async {
    if (_cart.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(saleRepositoryProvider).recordSale(
            businessId: widget.businessId,
            customerId: _customerId,
            lines: _cart.toSaleLines(),
          );

      ref.invalidate(salesProvider(widget.businessId));
      ref.invalidate(productsProvider(widget.businessId));
      ref.invalidate(dashboardStatsProvider(widget.businessId));
      ref.invalidate(insightsProvider(widget.businessId));

      if (!mounted) return;
      final sold = _cart.itemCount;
      final total = _cart.total;
      // Stays on the counter rather than popping: the next customer is already
      // waiting, and going back to a menu after every sale is the friction
      // this screen exists to remove.
      setState(() {
        _cart.clear();
        _customerId = null;
        _saving = false;
      });
      showToast(
          context,
          'Recorded $sold item${sold == 1 ? '' : 's'} · '
          '${formatPhp(total)}');
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, 'Could not record: $e', isError: true);
    }
  }
}

/// One product key.
///
/// Three earlier versions failed the same way and it is worth writing down.
/// A pale card left the middle empty; tinting it did not help; filling it with
/// the product's own colour cured the emptiness and replaced it with a grid of
/// clashing hues — brown beside magenta reads as arbitrary, not designed,
/// because a per-product colour is a decoration nobody chose.
///
/// So: no per-product colour at all. One accent, used where it earns its
/// place — on the price, which is the thing actually read at a counter — and
/// on the whole key once it is in the sale, which is the one distinction that
/// matters here. The key is sized to its contents rather than to a grid guess,
/// which is what finally removes the hole in the middle.
class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.inCart,
    required this.onTap,
    required this.onLongPress,
  });

  final Product product;
  final int inCart;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final selected = inCart > 0;
    final low = product.trackStock && product.stock <= 5;

    final ink = selected ? t.onAccent : t.ink;
    final quiet = selected ? t.onAccent.withValues(alpha: 0.75) : t.muted;

    return Material(
      color: selected ? t.accent : t.surface,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Gap.md, vertical: Gap.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: selected ? t.accent : t.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    Gap.w8,
                    Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.onAccent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Text(
                        '$inCart',
                        textAlign: TextAlign.center,
                        style: context.text.labelSmall?.copyWith(
                          color: t.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Gap.h4,
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                // Price hard left, stock hard right, so the two numbers can
                // never be mistaken for one another.
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      formatPhp(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(
                        // The number is what gets read; the accent is spent on
                        // it rather than sprayed across the whole key.
                        color: selected ? t.onAccent : t.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (product.trackStock)
                    Flexible(
                      child: Text(
                        // Always "left", never a bare number. Beside a peso
                        // amount a lone figure reads as a second price, and the
                        // word costs four characters. Only the weight changes
                        // when the shelf is running down — the label is a fact,
                        // the emphasis is the warning.
                        '${product.stock} left',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: context.text.bodySmall?.copyWith(
                          color: low && !selected ? t.warning : quiet,
                          fontWeight: low ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer, total, and the button that ends the sale.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.cart,
    required this.customers,
    required this.customerId,
    required this.saving,
    required this.onCustomerChanged,
    required this.onReview,
    required this.onRecord,
  });

  final SaleCart cart;
  final List<Customer> customers;
  final String? customerId;
  final bool saving;
  final ValueChanged<String?> onCustomerChanged;
  final VoidCallback? onReview;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: t.line),
          Gap.h12,
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: customerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Customer',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Walk-in'),
                    ),
                    for (final c in customers)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: saving ? null : onCustomerChanged,
                ),
              ),
              Gap.w12,
              // Tappable, because the grid deliberately hides the line items
              // and the owner still has to be able to check them.
              Flexible(
                child: InkWell(
                  onTap: onReview,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Gap.sm, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall,
                        ),
                        Text(
                          formatPhp(cart.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              context.text.titleLarge?.copyWith(color: t.ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Gap.h12,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRecord,
              child: saving
                  ? const ButtonSpinner()
                  : Text(
                      cart.isEmpty
                          ? 'Tap a product to start'
                          : 'Record sale · ${formatPhp(cart.total)}',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The lines behind the total, for checking before recording.
class _CartSheet extends StatefulWidget {
  const _CartSheet({required this.cart, required this.onChanged});

  final SaleCart cart;
  final VoidCallback onChanged;

  @override
  State<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends State<_CartSheet> {
  Future<void> _editDays(CartLine line) async {
    final chosen = await askQuantity(
      context,
      productName: line.product.name,
      current: line.days,
      title: 'For how many days?',
      unit: 'day',
    );
    if (chosen == null || !mounted) return;
    setState(() => widget.cart.setDays(line, chosen));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cart = widget.cart;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This sale', style: context.text.titleMedium),
          Gap.h12,
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final line in cart.lines.toList())
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.product.name,
                                style: context.text.bodyMedium
                                    ?.copyWith(color: t.ink),
                              ),
                              Text(
                                line.isRental
                                    ? '${line.qty} × '
                                        '${formatPhp(line.product.price)} a day'
                                    : '${line.qty} × '
                                        '${formatPhp(line.product.price)}',
                                style: context.text.bodySmall,
                              ),
                              // The counter has to be able to say how long
                              // something is out for. Without this a rental
                              // booked here is always one day, which is the
                              // wrong money and the wrong due date.
                              if (line.isRental)
                                InkWell(
                                  onTap: () => _editDays(line),
                                  borderRadius: BorderRadius.circular(Radii.sm),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.event_outlined,
                                            size: 14, color: t.accent),
                                        Gap.w4,
                                        Text(
                                          'For ${line.days} '
                                          '${line.days == 1 ? 'day' : 'days'}'
                                          ' — change',
                                          style: context.text.labelSmall
                                              ?.copyWith(color: t.accent),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          formatPhp(line.subtotal),
                          style:
                              context.text.bodyMedium?.copyWith(color: t.ink),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: t.danger,
                          onPressed: () {
                            setState(() => cart.remove(line));
                            widget.onChanged();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: t.line),
          Row(
            children: [
              Text('Total', style: context.text.bodyMedium),
              const Spacer(),
              Text(
                formatPhp(cart.total),
                style: context.text.titleLarge?.copyWith(color: t.ink),
              ),
            ],
          ),
          Gap.h16,
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to counter'),
          ),
        ],
      ),
    );
  }
}
