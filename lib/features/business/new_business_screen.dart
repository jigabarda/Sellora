import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/business_types.dart';
import '../../core/sellora_ui.dart';
import '../../data/repositories/business_repository.dart';
import '../../providers.dart';
import '../../util/ids.dart';

class NewBusinessScreen extends ConsumerStatefulWidget {
  const NewBusinessScreen({super.key});

  @override
  ConsumerState<NewBusinessScreen> createState() => _NewBusinessScreenState();
}

class _NewBusinessScreenState extends ConsumerState<NewBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();

  String? _type;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New business')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
            children: [
              SectionHeader(
                icon: Icons.storefront_outlined,
                title: 'Set up your business',
                subtitle: 'You can run more than one from this app',
                tone: context.t.accent,
              ),
              Gap.h24,
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Business name',
                  hintText: "e.g. Juan's Water Refilling",
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a business name'
                    : null,
              ),
              Gap.h12,
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Business type'),
                hint: const Text('Select business type'),
                items: kBusinessTypes
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(growable: false),
                onChanged: (value) => setState(() => _type = value),
                validator: (v) => v == null ? 'Select a business type' : null,
              ),
              Gap.h12,
              TextFormField(
                controller: _address,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Optional',
                ),
              ),
              Gap.h12,
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: '09XX-XXX-XXXX',
                ),
              ),
              Gap.h24,
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const ButtonSpinner()
                    : const Text('Create business'),
              ),
              Gap.h8,
              OutlinedButton(
                onPressed: _saving ? null : () => context.pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final uid = ref.read(authControllerProvider).userId;
      if (uid == null) {
        if (mounted) {
          showToast(context, 'Please sign in again to create a business.',
              isError: true);
        }
        return;
      }

      final business = Business(
        id: newLocalId('biz'),
        userId: uid,
        name: _name.text.trim(),
        type: _type!,
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        createdAt: DateTime.now(),
      );
      await ref.read(businessRepositoryProvider).insert(business);
      ref.invalidate(businessesProvider);
      if (!mounted) return;
      context.go('/business/${business.id}/dashboard');
    } catch (e) {
      if (mounted) {
        showToast(context, 'Could not save locally: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
