import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../data/quick_entry/quick_command.dart';
import '../../providers.dart';
import '../../util/ids.dart';

const _expenseCategories = [
  'Supplies',
  'Utilities',
  'Rent',
  'Transport',
  'Payroll',
  'Other',
];

IconData _categoryIcon(String category) => switch (category) {
      'Supplies' => Icons.inventory_2_outlined,
      'Utilities' => Icons.bolt_outlined,
      'Rent' => Icons.home_work_outlined,
      'Transport' => Icons.local_shipping_outlined,
      'Payroll' => Icons.groups_outlined,
      _ => Icons.receipt_long_outlined,
    };

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(expensesProvider(businessId));

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay alive together, so the default hero tag collides.
        heroTag: 'fab_expenses',
        onPressed: () => context.push('/business/$businessId/expenses/new'),
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add expense'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(expensesProvider(businessId));
          await ref.read(expensesProvider(businessId).future);
        },
        child: async.when(
          loading: () => const RefreshableFill(child: LoadingView()),
          error: (e, _) => RefreshableFill(
            child: ErrorView(
              error: e,
              onRetry: () => ref.invalidate(expensesProvider(businessId)),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return RefreshableFill(
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No expenses yet',
                  message:
                      'Track what the business spends so your profit figures '
                      'mean something.',
                  actionLabel: 'Add expense',
                  onAction: () =>
                      context.push('/business/$businessId/expenses/new'),
                ),
              );
            }

            final total = rows.fold<double>(0, (sum, e) => sum + e.amount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 120),
              children: [
                SelloraCard(
                  padding: const EdgeInsets.all(Gap.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total recorded',
                                style: context.text.labelSmall),
                            Gap.h4,
                            Text(formatPhp(total),
                                style: context.text.headlineSmall),
                          ],
                        ),
                      ),
                      SelloraPill(
                        label:
                            '${rows.length} entr${rows.length == 1 ? 'y' : 'ies'}',
                      ),
                    ],
                  ),
                ),
                Gap.h16,
                ...rows.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: _ExpenseCard(
                      expense: e,
                      onEdit: () => context.push(
                        '/business/$businessId/expenses/edit/${e.id}',
                      ),
                      onDelete: () => _delete(context, ref, e),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Expense expense) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete expense',
      message:
          'Delete this ${formatPhp(expense.amount)} ${expense.category.toLowerCase()} '
          'expense? Your reports will change to match.',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(expenseRepositoryProvider).delete(expense.id);
      ref.invalidate(expensesProvider(businessId));
      if (context.mounted) showToast(context, 'Expense deleted');
    } catch (e) {
      if (context.mounted) {
        showToast(context, 'Could not delete: $e', isError: true);
      }
    }
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return SelloraCard(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.sm, Gap.md),
      onTap: onEdit,
      child: Row(
        children: [
          // Money out is `danger` throughout — the Expenses metric in
          // Reports already uses it. The tint is soft enough not to read as
          // an error, and the icon carries the category.
          IconTile(icon: _categoryIcon(expense.category), tone: t.danger),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.category,
                  style: context.text.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  expense.note.isEmpty
                      ? formatTimestamp(expense.at)
                      : '${expense.note} · ${formatTimestamp(expense.at)}',
                  style: context.text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Gap.w8,
          Text(formatPhp(expense.amount), style: context.text.titleSmall),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: t.muted),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: t.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    super.key,
    required this.businessId,
    this.expenseId,
    this.prefill,
  });

  final String businessId;
  final String? expenseId;

  /// Seeded by Quick Entry. The form is the confirmation step — nothing is
  /// written until the user taps save here, so a wrong parse costs an edit
  /// rather than a bad row.
  final AddExpenseCommand? prefill;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  String _category = _expenseCategories.first;
  DateTime _at = DateTime.now();
  bool _saving = false;
  bool _loading = false;
  Expense? _existing;

  bool get _isEdit => widget.expenseId != null;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null && !_isEdit) {
      _amount.text = prefill.amount.toStringAsFixed(2);
      _note.text = prefill.note;
      if (_expenseCategories.contains(prefill.category)) {
        _category = prefill.category;
      }
    }
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final e = await ref
            .read(expenseRepositoryProvider)
            .getById(widget.expenseId!);
        if (!mounted) return;
        setState(() {
          _existing = e;
          _loading = false;
          if (e != null) {
            _amount.text = e.amount.toStringAsFixed(2);
            _note.text = e.note;
            _category = _expenseCategories.contains(e.category)
                ? e.category
                : _expenseCategories.last;
            _at = e.at;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit expense' : 'Add expense')),
      body: _loading
          ? const LoadingView()
          : (_isEdit && _existing == null)
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Expense not found',
                  message: 'It may have been deleted from another screen.',
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
                    children: [
                      TextFormField(
                        controller: _amount,
                        autofocus: !_isEdit,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '₱ ',
                        ),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      Gap.h12,
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: _expenseCategories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Row(
                                    children: [
                                      Icon(_categoryIcon(c), size: 17),
                                      Gap.w8,
                                      Text(c),
                                    ],
                                  ),
                                ))
                            .toList(growable: false),
                        onChanged: (v) => setState(
                            () => _category = v ?? _expenseCategories.first),
                      ),
                      Gap.h12,
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Date'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(formatDay(_at),
                                    style: context.text.bodyLarge),
                              ),
                              Icon(Icons.calendar_today_outlined,
                                  size: 17, color: context.t.muted),
                            ],
                          ),
                        ),
                      ),
                      Gap.h12,
                      TextFormField(
                        controller: _note,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                          hintText: 'Optional',
                        ),
                      ),
                      Gap.h24,
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const ButtonSpinner()
                            : Text(_isEdit ? 'Save changes' : 'Add expense'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      // Expenses are recorded after the fact, never scheduled ahead.
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _at = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _at.hour,
            _at.minute,
          ));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final expense = Expense(
        id: _existing?.id ?? newLocalId('exp'),
        businessId: widget.businessId,
        amount: double.parse(_amount.text.trim()),
        category: _category,
        note: _note.text.trim(),
        at: _at,
      );

      if (_isEdit) {
        await repo.update(expense);
      } else {
        await repo.insert(expense);
      }

      ref.invalidate(expensesProvider(widget.businessId));
      ref.invalidate(dashboardStatsProvider(widget.businessId));
      if (!mounted) return;
      showToast(context, _isEdit ? 'Expense updated' : 'Expense added');
      context.pop();
    } catch (err) {
      if (mounted) showToast(context, 'Save failed: $err', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
