import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/models/entities.dart';
import '../../providers.dart';
import '../../util/ids.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({
    super.key,
    required this.businessId,
    this.customerId,
  });

  final String businessId;
  final String? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();

  bool _saving = false;
  bool _loading = false;
  Customer? _existing;

  bool get _isEdit => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final c = await ref
            .read(customerRepositoryProvider)
            .getById(widget.customerId!);
        if (!mounted) return;
        setState(() {
          _existing = c;
          _loading = false;
          if (c != null) {
            _name.text = c.name;
            _phone.text = c.phone;
            _email.text = c.email;
            _notes.text = c.notes;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit customer' : 'Add customer')),
      body: _loading
          ? const LoadingView()
          : (_isEdit && _existing == null)
              ? const EmptyState(
                  icon: Icons.person_off_outlined,
                  title: 'Customer not found',
                  message: 'It may have been deleted from another screen.',
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding:
                        const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'e.g. Aling Nena',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter a name'
                            : null,
                      ),
                      Gap.h12,
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          hintText: '09XX-XXX-XXXX',
                        ),
                      ),
                      Gap.h12,
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return null;
                          return value.contains('@')
                              ? null
                              : 'Enter a valid email';
                        },
                      ),
                      Gap.h12,
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Delivery preferences, credit terms...',
                        ),
                      ),
                      Gap.h24,
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const ButtonSpinner()
                            : Text(_isEdit ? 'Save changes' : 'Add customer'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final customer = Customer(
        id: _existing?.id ?? newLocalId('cus'),
        businessId: widget.businessId,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text.trim(),
        createdAt: _existing?.createdAt ?? DateTime.now(),
      );

      if (_isEdit) {
        await repo.update(customer);
      } else {
        await repo.insert(customer);
      }

      ref.invalidate(customersProvider(widget.businessId));
      if (!mounted) return;
      showToast(context, _isEdit ? 'Customer updated' : 'Customer added');
      context.pop();
    } catch (e) {
      if (mounted) showToast(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
