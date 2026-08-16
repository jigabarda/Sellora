import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../data/notebook/notebook_line.dart';
import '../../data/notebook/notebook_parser.dart';
import '../../providers.dart';

/// Photograph a page of the notebook; check what was read; record it.
///
/// The rule Quick Entry established holds here too, and matters more: reading
/// never writes. Recognition produces a preview, the preview is editable, and
/// the owner's tap on "Record" is the only thing that touches the database.
/// That is what makes an imperfect recogniser safe to ship — a misread line
/// costs a glance, not a corrupted book.
///
/// Lines that proved themselves against the price list start ticked. Lines that
/// did not start unticked, every time. The owner opting in to a doubtful line
/// is a decision; the app opting in on their behalf would be a guess wearing a
/// decision's clothes.
class NotebookCaptureScreen extends ConsumerStatefulWidget {
  const NotebookCaptureScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<NotebookCaptureScreen> createState() =>
      _NotebookCaptureScreenState();
}

class _NotebookCaptureScreenState extends ConsumerState<NotebookCaptureScreen> {
  List<NotebookLine>? _lines;
  final _selected = <int>{};
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider(widget.businessId)).valueOrNull ?? const [];
    final customers =
        ref.watch(customersProvider(widget.businessId)).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Scan a page')),
      body: _busy
          ? const LoadingView()
          : _lines == null
              ? _Intro(onPick: (source) => _pick(source, products, customers))
              : _Preview(
                  lines: _lines!,
                  selected: _selected,
                  error: _error,
                  onToggle: _toggle,
                  onEdit: (i) => _edit(i, products, customers),
                  onRetake: () => setState(() {
                    _lines = null;
                    _selected.clear();
                    _error = null;
                  }),
                ),
      bottomNavigationBar: _lines == null || _busy
          ? null
          : _RecordBar(
              lines: _lines!,
              selected: _selected,
              onRecord: _record,
            ),
    );
  }

  Future<void> _pick(
    ImageSource source,
    List<Product> products,
    List<Customer> customers,
  ) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        // Downscaled before it reaches the recogniser. A 12-megapixel photo of
        // a notebook page is slower to process and no more legible than this,
        // and the phones this runs on do not have the memory to spare.
        maxWidth: 2000,
        imageQuality: 90,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
      return;
    }
    if (file == null) return; // Backed out of the picker.

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final text = await ref.read(textRecogniserProvider).recognise(file.path);
      final page = const NotebookParser()
          .parse(text, products: products, customers: customers);
      if (!mounted) return;
      setState(() {
        _lines = page.lines;
        _selected
          ..clear()
          ..addAll(_defaultSelection(page.lines));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not read that image: $e';
      });
    }
  }

  /// Only the lines that reconciled. Everything else is opt-in.
  Set<int> _defaultSelection(List<NotebookLine> lines) {
    final out = <int>{};
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].status == LineStatus.reconciled) out.add(i);
    }
    return out;
  }

  void _toggle(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  Future<void> _edit(
    int index,
    List<Product> products,
    List<Customer> customers,
  ) async {
    final edited = await showModalBottomSheet<NotebookLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LineEditor(
        line: _lines![index],
        products: products.where((p) => p.active).toList(),
        customers: customers,
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _lines![index] = edited;
      // A line the owner has just corrected is one they have looked at, so it
      // becomes eligible — but ticking it is still their move, not ours.
      if (!edited.isRecordable) _selected.remove(index);
    });
  }

  Future<void> _record() async {
    final chosen = _selected.toList()..sort();
    if (chosen.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(saleRepositoryProvider);
    var recorded = 0;
    final failures = <String>[];

    // One sale per line rather than one basket: the lines have different
    // customers, and collapsing them would lose which refill was whose.
    for (final i in chosen) {
      final line = _lines![i];
      final product = line.product;
      if (product == null) continue;
      try {
        await repo.recordSale(
          businessId: widget.businessId,
          customerId: line.customer?.id,
          lines: [
            (
              productId: product.id,
              name: product.name,
              qty: line.quantity,
              unitPrice: product.price,
            ),
          ],
        );
        recorded++;
      } on StateError catch (e) {
        // Almost always insufficient stock. The rest of the page still goes
        // in — losing eight good lines because the ninth ran the shelf down
        // would be a worse outcome than a partial page.
        failures.add('${product.name}: ${e.message}');
      }
    }

    if (!mounted) return;

    ref.invalidate(salesProvider(widget.businessId));
    ref.invalidate(productsProvider(widget.businessId));
    ref.invalidate(dashboardStatsProvider(widget.businessId));
    ref.invalidate(insightsProvider(widget.businessId));

    if (failures.isEmpty) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded $recorded ${recorded == 1 ? 'sale' : 'sales'}',
          ),
        ),
      );
      return;
    }

    setState(() {
      _busy = false;
      _selected.clear();
      _error = 'Recorded $recorded. Could not record '
          '${failures.length}: ${failures.join('; ')}';
    });
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});

  final void Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, 40),
      children: [
        const EmptyState(
          icon: Icons.document_scanner_outlined,
          title: 'Photograph your notebook',
          message: 'One page at a time. Sellora reads the lines, checks each '
              'one against your price list, and shows you what it found '
              'before anything is saved.',
          compact: true,
        ),
        Gap.h8,
        FilledButton.icon(
          onPressed: () => onPick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: const Text('Take a photo'),
        ),
        Gap.h12,
        OutlinedButton.icon(
          onPressed: () => onPick(ImageSource.gallery),
          icon: const Icon(Icons.image_outlined, size: 18),
          label: const Text('Choose an existing photo'),
        ),
        Gap.h24,
        const _Tips(),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  static const _lines = [
    'Lay the page flat and fill the frame with it.',
    'Write the amount beside each line — that is what Sellora checks against.',
    'One line per sale: name, how many, what, how much.',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('For the best reading', style: context.text.labelSmall),
        Gap.h8,
        for (final line in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $line', style: context.text.bodySmall),
          ),
        Gap.h12,
        Text(
          'Handwriting is harder to read than print. Anything Sellora is not '
          'sure of is left unticked for you to check — it is never guessed '
          'into your books.',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.lines,
    required this.selected,
    required this.error,
    required this.onToggle,
    required this.onEdit,
    required this.onRetake,
  });

  final List<NotebookLine> lines;
  final Set<int> selected;
  final String? error;
  final void Function(int) onToggle;
  final void Function(int) onEdit;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final page = NotebookPage(lines: lines);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
      children: [
        if (error != null) ...[
          SelloraCard(
            color: t.dangerSoft,
            border: false,
            child: Text(
              error!,
              style: context.text.bodySmall?.copyWith(color: t.danger),
            ),
          ),
          Gap.h12,
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                page.isBlank
                    ? 'Nothing readable on that photo'
                    : '${page.reconciledCount} of ${lines.length} lines '
                        'added up',
                style: context.text.bodyMedium,
              ),
            ),
            TextButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retake'),
            ),
          ],
        ),
        Gap.h8,
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: _LineTile(
              line: lines[i],
              checked: selected.contains(i),
              onToggle: () => onToggle(i),
              onEdit: () => onEdit(i),
            ),
          ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.checked,
    required this.onToggle,
    required this.onEdit,
  });

  final NotebookLine line;
  final bool checked;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (label, tone) = switch (line.status) {
      LineStatus.reconciled => ('Adds up', PillTone.success),
      LineStatus.needsReview => ('Check this', PillTone.warning),
      LineStatus.unreadable => ("Couldn't read", PillTone.danger),
      LineStatus.ignored => ('Skipped', PillTone.neutral),
    };

    final selectable = line.isRecordable;

    return SelloraCard(
      onTap: selectable ? onToggle : null,
      borderColor: checked ? t.accent : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectable)
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: (_) => onToggle(),
                visualDensity: VisualDensity.compact,
              ),
            )
          else
            const SizedBox(width: 24, height: 24),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.product == null
                            ? line.raw.trim()
                            : '${line.quantity} × ${line.product!.name}',
                        style: context.text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Gap.w8,
                    if (line.product != null)
                      Text(
                        formatPhp(line.total),
                        style: context.text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                // The page's own words, so the owner can check the tile
                // against the notebook in their other hand. Skipped when no
                // product was identified, because the heading above is then
                // already the raw text and printing it twice reads as a bug.
                if (line.product != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    line.raw.trim(),
                    style: context.text.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
                if (line.customer != null) ...[
                  const SizedBox(height: 2),
                  Text(line.customer!.name, style: context.text.bodySmall),
                ],
                if (line.note != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    line.note!,
                    style: context.text.bodySmall?.copyWith(color: t.warning),
                  ),
                ],
                Gap.h8,
                Row(
                  children: [
                    SelloraPill(label: label, tone: tone),
                    const Spacer(),
                    if (line.status != LineStatus.ignored)
                      TextButton(
                        onPressed: onEdit,
                        child: const Text('Edit'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordBar extends StatelessWidget {
  const _RecordBar({
    required this.lines,
    required this.selected,
    required this.onRecord,
  });

  final List<NotebookLine> lines;
  final Set<int> selected;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final chosen = selected.map((i) => lines[i]).toList();
    final total = chosen.fold<double>(0, (sum, l) => sum + l.total);

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
                child: Text(
                  '${chosen.length} selected',
                  style: context.text.bodyMedium,
                ),
              ),
              Text(
                formatPhp(total),
                style: context.text.titleMedium,
              ),
            ],
          ),
          Gap.h12,
          FilledButton(
            onPressed: chosen.isEmpty ? null : onRecord,
            child: Text(
              chosen.isEmpty
                  ? 'Nothing selected'
                  : 'Record ${chosen.length} '
                      '${chosen.length == 1 ? 'sale' : 'sales'}',
            ),
          ),
        ],
      ),
    );
  }
}

/// Correcting one line: the product, how many, and whose it was.
class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.line,
    required this.products,
    required this.customers,
  });

  final NotebookLine line;
  final List<Product> products;
  final List<Customer> customers;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late Product? _product = widget.line.product;
  late Customer? _customer = widget.line.customer;
  late int _qty = widget.line.quantity;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        MediaQuery.of(context).viewInsets.bottom + Gap.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Correct this line', style: context.text.titleMedium),
          Gap.h4,
          Text(
            widget.line.raw.trim(),
            style: context.text.bodySmall?.copyWith(color: t.muted),
          ),
          Gap.h16,
          DropdownButtonFormField<Product>(
            initialValue: _product,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: [
              for (final p in widget.products)
                DropdownMenuItem(
                  value: p,
                  child: Text('${p.name} — ${formatPhp(p.price)}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (p) => setState(() => _product = p),
          ),
          Gap.h12,
          DropdownButtonFormField<Customer?>(
            initialValue: _customer,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Customer'),
            items: [
              const DropdownMenuItem<Customer?>(
                value: null,
                child: Text('Walk-in'),
              ),
              for (final c in widget.customers)
                DropdownMenuItem(value: c, child: Text(c.name)),
            ],
            onChanged: (c) => setState(() => _customer = c),
          ),
          Gap.h12,
          Row(
            children: [
              Text('Quantity', style: context.text.bodyMedium),
              const Spacer(),
              IconButton.outlined(
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                child: Text('$_qty', style: context.text.titleMedium),
              ),
              IconButton.outlined(
                onPressed: () => setState(() => _qty++),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
          Gap.h16,
          if (_product != null)
            Text(
              'Records as ${formatPhp(_product!.price * _qty)}',
              style: context.text.bodyMedium,
            ),
          Gap.h16,
          FilledButton(
            onPressed: _product == null ? null : _save,
            child: const Text('Save line'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final product = _product!;
    final written = widget.line.writtenAmount;
    // Re-run the same check the parser ran. A correction that now agrees with
    // the page earns the same green tick a clean reading would have — the
    // owner should not be able to tell which lines the app got right first
    // time and which they fixed.
    final adds = written != null && (product.price * _qty - written).abs() < 0.005;

    Navigator.of(context).pop(
      widget.line.copyWith(
        product: product,
        customer: _customer,
        clearCustomer: _customer == null,
        quantity: _qty,
        status: adds ? LineStatus.reconciled : LineStatus.needsReview,
        note: adds ? null : 'Corrected by hand',
        clearNote: adds,
      ),
    );
  }
}
