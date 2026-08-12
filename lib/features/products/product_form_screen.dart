import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/product_units.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import '../../util/ids.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.businessId,
    this.productId,
  });

  final String businessId;
  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '0');

  String? _categoryId;
  String _unit = kDefaultProductUnit;
  bool _trackStock = true;
  bool _active = true;

  bool _saving = false;
  bool _loading = false;
  Product? _existing;

  bool get _isEdit => widget.productId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final p = await ref
            .read(productRepositoryProvider)
            .getById(widget.productId!);
        if (!mounted) return;
        setState(() {
          _existing = p;
          _loading = false;
          if (p != null) {
            _name.text = p.name;
            _description.text = p.description;
            _sku.text = p.sku;
            _price.text = p.price.toStringAsFixed(2);
            _stock.text = p.stock.toString();
            _categoryId = p.categoryId;
            _unit = p.unit;
            _trackStock = p.trackStock;
            _active = p.active;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sku.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoriesProvider(widget.businessId)).valueOrNull ??
            const <Category>[];
    // A category deleted from another screen leaves a stale id behind; fall
    // back to uncategorized rather than tripping the dropdown's assertion.
    final selectedCategory =
        categories.any((c) => c.id == _categoryId) ? _categoryId : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit product' : 'Add product'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, color: context.t.danger),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : (_isEdit && _existing == null)
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Product not found',
                  message: 'It may have been deleted from another screen.',
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
                    children: [
                      _card(
                        icon: Icons.inventory_2_outlined,
                        title: 'Details',
                        subtitle: 'What you are selling',
                        children: [
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Product name',
                              hintText: 'e.g. 5-Gallon Water Refill',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Enter a product name'
                                : null,
                          ),
                          Gap.h12,
                          TextFormField(
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              prefixText: '₱ ',
                            ),
                            validator: (v) {
                              final n = double.tryParse((v ?? '').trim());
                              if (n == null || n < 0) {
                                return 'Enter a valid price';
                              }
                              return null;
                            },
                          ),
                          Gap.h12,
                          TextFormField(
                            controller: _description,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              hintText: 'Optional',
                            ),
                          ),
                        ],
                      ),
                      Gap.h12,
                      _card(
                        icon: Icons.warehouse_outlined,
                        title: 'Stock',
                        subtitle: 'How inventory behaves',
                        children: [
                          SwitchListTile.adaptive(
                            value: _trackStock,
                            onChanged: (v) => setState(() => _trackStock = v),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Track stock',
                              style: context.text.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Turn off for services or anything that never runs out.',
                              style: context.text.bodySmall,
                            ),
                          ),
                          if (_trackStock) ...[
                            Gap.h8,
                            TextFormField(
                              controller: _stock,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Stock on hand',
                                helperText: _isEdit
                                    ? 'Changes are written to stock history.'
                                    : 'Becomes the starting quantity.',
                              ),
                              validator: (v) {
                                // Only enforced while tracking; the field is
                                // gone otherwise.
                                if (!_trackStock) return null;
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n < 0) {
                                  return 'Enter a valid stock';
                                }
                                return null;
                              },
                            ),
                          ],
                          Gap.h12,
                          DropdownButtonFormField<String>(
                            initialValue: withStoredUnit(_unit).contains(_unit)
                                ? _unit
                                : kDefaultProductUnit,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Unit'),
                            items: withStoredUnit(_unit)
                                .map((u) =>
                                    DropdownMenuItem(value: u, child: Text(u)))
                                .toList(growable: false),
                            onChanged: (v) => setState(
                                () => _unit = v ?? kDefaultProductUnit),
                          ),
                        ],
                      ),
                      Gap.h12,
                      _card(
                        icon: Icons.sell_outlined,
                        title: 'Organisation',
                        subtitle: 'Grouping and identifiers',
                        trailing: TextButton(
                          onPressed: () => context.push(
                              '/business/${widget.businessId}/categories'),
                          child: const Text('Manage'),
                        ),
                        children: [
                          DropdownButtonFormField<String?>(
                            initialValue: selectedCategory,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Category',
                              helperText: categories.isEmpty
                                  ? 'No categories yet — tap Manage to add one.'
                                  : null,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No category'),
                              ),
                              ...categories.map(
                                (c) => DropdownMenuItem<String?>(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => _categoryId = v),
                          ),
                          Gap.h12,
                          TextFormField(
                            controller: _sku,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'SKU',
                              hintText: 'Optional',
                            ),
                          ),
                          // Matches the web form, which only offers this when
                          // editing: a product is always created active.
                          if (_isEdit) ...[
                            Gap.h4,
                            SwitchListTile.adaptive(
                              value: _active,
                              onChanged: (v) => setState(() => _active = v),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Active',
                                style: context.text.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Inactive products stay in your records but cannot be sold.',
                                style: context.text.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Gap.h24,
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const ButtonSpinner()
                            : Text(_isEdit ? 'Save changes' : 'Add product'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: icon,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          Gap.h16,
          ...children,
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(productRepositoryProvider);
      final price = double.parse(_price.text.trim());
      // An untracked product has no inventory; its stock column stays at 0.
      final stock = _trackStock ? int.parse(_stock.text.trim()) : 0;

      if (!_isEdit) {
        await repo.insert(Product(
          id: newLocalId('prd'),
          businessId: widget.businessId,
          categoryId: _categoryId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          sku: _sku.text.trim(),
          unit: _unit,
          price: price,
          stock: stock,
          trackStock: _trackStock,
          active: true,
          createdAt: DateTime.now(),
        ));
      } else {
        final existing = _existing;
        if (existing == null) return;
        // Turning tracking off zeroes the stock, so only a still-tracked
        // product produces an adjustment worth recording.
        final delta = _trackStock ? stock - existing.stock : 0;
        await repo.update(Product(
          id: existing.id,
          businessId: existing.businessId,
          categoryId: _categoryId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          sku: _sku.text.trim(),
          unit: _unit,
          price: price,
          // Stock moves through applyStockDelta below so the ledger stays the
          // single source of truth for inventory changes.
          stock: _trackStock ? existing.stock : 0,
          trackStock: _trackStock,
          active: _active,
          createdAt: existing.createdAt,
        ));
        if (delta != 0) {
          await repo.applyStockDelta(
            businessId: widget.businessId,
            productId: existing.id,
            delta: delta,
            reason: 'adjustment',
            refId: existing.id,
            note: 'Manual stock edit',
          );
        }
      }

      _refresh();
      if (!mounted) return;
      showToast(context, _isEdit ? 'Product updated' : 'Product added');
      context.pop();
    } catch (e) {
      if (mounted) showToast(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = _existing;
    if (existing == null) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete product',
      message:
          'Delete ${existing.name}? If it has ever been sold this will fail — '
          'switch it to inactive instead so your sales history stays intact.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(productRepositoryProvider).delete(existing.id);
      _refresh();
      if (!mounted) return;
      showToast(context, '${existing.name} deleted');
      context.pop();
    } catch (e) {
      // sale_lines.product_id is ON DELETE RESTRICT, so a sold product cannot
      // be removed. Say what to do instead of surfacing a raw SQL error.
      if (mounted) {
        showToast(
          context,
          'This product has recorded sales and cannot be deleted. '
          'Turn off "Active" to hide it from new sales.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _refresh() {
    ref.invalidate(productsProvider(widget.businessId));
    ref.invalidate(dashboardStatsProvider(widget.businessId));
    ref.invalidate(categoryUsageProvider(widget.businessId));
    ref.invalidate(stockLedgerProvider(widget.businessId));
  }
}
