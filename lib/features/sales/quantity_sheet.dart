import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sellora_ui.dart';

/// Asks for a quantity directly, instead of making the owner tap `+` for it.
///
/// The stepper is fine for two or three. It is not fine for fifty, and fifty is
/// an ordinary order at a water station — one tap per unit is the kind of thing
/// that makes someone keep using the notebook instead.
///
/// Returns the chosen quantity, or null if the sheet was dismissed. Never
/// returns something outside 1..[max]; the caller does not have to re-check.
Future<int?> askQuantity(
  BuildContext context, {
  required String productName,
  required int current,
  int? max,
  String title = 'How many?',
  String unit = 'item',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _QuantitySheet(
      productName: productName,
      current: current,
      max: max,
      title: title,
      unit: unit,
    ),
  );
}

class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({
    required this.productName,
    required this.current,
    required this.max,
    required this.title,
    required this.unit,
  });

  final String productName;
  final int current;
  final String title;

  /// What is being counted. Days need different round numbers from chairs —
  /// nobody rents anything for a hundred days.
  final String unit;

  /// Stock ceiling, or null when the product does not track stock.
  final int? max;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late final _controller = TextEditingController(text: '${widget.current}');
  late final _focus = FocusNode();
  String? _error;

  /// Round numbers someone actually orders by. Anything above the stock
  /// ceiling is dropped rather than shown disabled — a chip you cannot press
  /// is just a question you have to answer twice.
  static const _itemShortcuts = [5, 10, 20, 50, 100];
  static const _dayShortcuts = [1, 2, 3, 7, 14];

  @override
  void initState() {
    super.initState();
    // Selected, not just focused: the first keystroke should replace what is
    // there rather than append to it.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  int? get _parsed => int.tryParse(_controller.text.trim());

  void _submit() {
    final value = _parsed;
    if (value == null || value < 1) {
      setState(() => _error = 'Enter at least one ${widget.unit}');
      return;
    }
    if (widget.max != null && value > widget.max!) {
      setState(() => _error = 'Only ${widget.max} left in stock');
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final shortcuts =
        (widget.unit == 'day' ? _dayShortcuts : _itemShortcuts)
            .where((n) => widget.max == null || n <= widget.max!)
            .toList(growable: false);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        MediaQuery.of(context).viewInsets.bottom + Gap.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.text.titleMedium),
          Gap.h4,
          Text(
            widget.max == null
                ? widget.productName
                : '${widget.productName} · ${widget.max} in stock',
            style: context.text.bodySmall,
          ),
          Gap.h16,
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(signed: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: context.text.displaySmall?.copyWith(color: t.ink),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              errorText: _error,
              contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
            ),
          ),
          if (shortcuts.isNotEmpty) ...[
            Gap.h12,
            Wrap(
              spacing: Gap.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final n in shortcuts)
                  ActionChip(
                    label: Text('$n'),
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _controller.text = '$n';
                        _controller.selection = TextSelection.collapsed(
                          offset: _controller.text.length,
                        );
                      });
                    },
                  ),
              ],
            ),
          ],
          Gap.h16,
          FilledButton(
            onPressed: _submit,
            child: Text(widget.unit == 'day' ? 'Set days' : 'Set quantity'),
          ),
        ],
      ),
    );
  }
}
