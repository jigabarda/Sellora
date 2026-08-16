import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/quick_entry/quick_command.dart';
import '../../data/quick_entry/quick_entry_parser.dart';
import '../../providers.dart';

/// Type what happened; land on the right form with the fields filled in.
///
/// Nothing here writes. The interpretation below the field is feedback, not a
/// confirmation — the form it opens is the confirmation, and its save button is
/// the commit. That is what allows the parser to be imperfect: a wrong reading
/// costs an edit on a form the user was going to fill anyway.
class QuickEntryScreen extends ConsumerStatefulWidget {
  const QuickEntryScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends ConsumerState<QuickEntryScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The whole point is speed, so the keyboard should already be up.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsProvider(widget.businessId)).valueOrNull ?? const [];
    final customers =
        ref.watch(customersProvider(widget.businessId)).valueOrNull ?? const [];

    final command = _input.text.trim().isEmpty
        ? null
        : const QuickEntryParser().parse(
            _input.text,
            products: products,
            customers: customers,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Quick entry')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
        children: [
          TextField(
            controller: _input,
            focusNode: _focus,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _continue(command),
            decoration: const InputDecoration(
              hintText: '2 purified refill kay Aling Nena',
              prefixIcon: Icon(Icons.bolt_outlined, size: 20),
            ),
          ),
          Gap.h16,
          if (command != null) _Interpretation(command: command),
          if (command != null) ...[
            Gap.h16,
            FilledButton(
              onPressed: () => _continue(command),
              child: Text(
                command is UnparsedCommand ? 'Open a blank form' : 'Continue',
              ),
            ),
          ],
          Gap.h24,
          const _Examples(),
        ],
      ),
    );
  }

  void _continue(QuickCommand? command) {
    final id = widget.businessId;
    switch (command) {
      case RecordSaleCommand():
        context.pushReplacement('/business/$id/sales/new', extra: command);
      case AddExpenseCommand():
        context.pushReplacement('/business/$id/expenses/new', extra: command);
      case UnparsedCommand():
      case null:
        // Nothing understood is not a dead end: the empty sale form is where
        // the user would have started anyway.
        context.pushReplacement('/business/$id/sales/new');
    }
  }
}

/// What the parser made of the input, in the user's own terms.
class _Interpretation extends StatelessWidget {
  const _Interpretation({required this.command});

  final QuickCommand command;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return switch (command) {
      RecordSaleCommand(:final product, :final quantity, :final customer) =>
        _Row(
          icon: Icons.point_of_sale_outlined,
          tone: t.success,
          title: 'Sale — ${formatPhp(product.price * quantity)}',
          detail: '$quantity × ${product.name}'
              '${customer == null ? '' : ' for ${customer.name}'}',
        ),
      AddExpenseCommand(:final amount, :final category) => _Row(
          icon: Icons.receipt_long_outlined,
          tone: t.danger,
          title: 'Expense — ${formatPhp(amount)}',
          detail: category,
        ),
      // Says what it could not do rather than guessing. Seeing the miss is
      // itself useful — it teaches which phrasings work.
      UnparsedCommand() => _Row(
          icon: Icons.help_outline,
          tone: t.muted,
          title: "Couldn't read that",
          detail: 'Try a quantity and a product name, or an amount and what '
              'it was for.',
        ),
    };
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SelloraCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, tone: tone),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(detail, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples();

  static const _lines = [
    '2 purified refill',
    'dalawang ice tube kay Aling Nena',
    '500 gas',
    'bayad kuryente 3400',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Things you can type', style: context.text.labelSmall),
        Gap.h8,
        for (final line in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $line', style: context.text.bodySmall),
          ),
        Gap.h12,
        Text(
          'Whatever it works out, you get the normal form to check before '
          'anything is saved.',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}
