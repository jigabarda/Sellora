import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';

/// Asks how much to take off a sale, in pesos or in percent.
///
/// Both are asked for because both are how people actually say it — "bawas
/// singkwenta" and "ten percent" are the same conversation — but only one is
/// returned. The peso amount is what a percentage means today, and it is what
/// stays true in the record a year from now when prices have changed; a stored
/// percentage would quietly re-price every old sale it appears on.
///
/// Returns the amount off in pesos, or null if the sheet was dismissed.
/// Never returns something outside 0..[subtotal].
Future<double?> askDiscount(
  BuildContext context, {
  required double subtotal,
  double current = 0,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DiscountSheet(subtotal: subtotal, current: current),
  );
}

enum _Mode { peso, percent }

class _DiscountSheet extends StatefulWidget {
  const _DiscountSheet({required this.subtotal, required this.current});

  final double subtotal;
  final double current;

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  late final _controller = TextEditingController(
    text: widget.current > 0 ? _trim(widget.current) : '',
  );
  late final _focus = FocusNode();
  _Mode _mode = _Mode.peso;
  String? _error;

  /// The discounts a small shop actually gives. Percentages because that is
  /// how the common ones are named — senior and PWD discounts are twenty per
  /// cent by law, and everybody here knows that number.
  static const _percentShortcuts = [5, 10, 15, 20];

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
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

  double? get _typed => double.tryParse(_controller.text.trim());

  /// What the typed number comes to in pesos, or null if it is not a number.
  double? get _amount {
    final v = _typed;
    if (v == null) return null;
    return _mode == _Mode.peso ? v : widget.subtotal * v / 100;
  }

  void _submit() {
    if (_controller.text.trim().isEmpty) {
      // An empty box means "no discount", which is a real answer and the way
      // to take one back off.
      Navigator.of(context).pop(0.0);
      return;
    }
    final amount = _amount;
    if (amount == null || amount < 0) {
      setState(() => _error = 'Enter an amount to take off');
      return;
    }
    if (_mode == _Mode.percent && _typed! > 100) {
      setState(() => _error = 'A discount cannot be more than 100%');
      return;
    }
    if (amount > widget.subtotal) {
      setState(() => _error =
          'That is more than the sale (${formatPhp(widget.subtotal)})');
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final amount = _amount;
    final valid = amount != null && amount >= 0 && amount <= widget.subtotal;

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
          Text('Discount', style: context.text.titleMedium),
          Gap.h4,
          Text(
            'Sale is ${formatPhp(widget.subtotal)}',
            style: context.text.bodySmall,
          ),
          Gap.h16,
          SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.peso, label: Text('Pesos off')),
              ButtonSegment(value: _Mode.percent, label: Text('Percent off')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _error = null;
            }),
          ),
          Gap.h16,
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: context.text.displaySmall?.copyWith(color: t.ink),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '0',
              errorText: _error,
              prefixText: _mode == _Mode.peso ? '₱ ' : null,
              suffixText: _mode == _Mode.percent ? '%' : null,
              contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
            ),
          ),
          if (_mode == _Mode.percent) ...[
            Gap.h12,
            Wrap(
              spacing: Gap.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final n in _percentShortcuts)
                  ActionChip(
                    label: Text('$n%'),
                    onPressed: () => setState(() {
                      _error = null;
                      _controller.text = '$n';
                      _controller.selection = TextSelection.collapsed(
                        offset: _controller.text.length,
                      );
                    }),
                  ),
              ],
            ),
          ],
          Gap.h16,
          // The number that matters is what the customer pays, so it is shown
          // before the button rather than found out afterwards.
          Row(
            children: [
              Text('Customer pays', style: context.text.bodyMedium),
              const Spacer(),
              Text(
                formatPhp(valid ? widget.subtotal - amount : widget.subtotal),
                style: context.text.titleLarge?.copyWith(color: t.ink),
              ),
            ],
          ),
          Gap.h16,
          FilledButton(
            onPressed: _submit,
            child: const Text('Apply discount'),
          ),
        ],
      ),
    );
  }
}
