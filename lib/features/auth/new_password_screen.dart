import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/auth/auth_controller.dart';
import '../../providers.dart';

/// Offered straight after a restore, so a forgotten password has a way out.
///
/// The password itself cannot be recovered — it is a one-way hash and there is
/// no server to mail a link from. What can be re-established is proof that the
/// account is yours, and the backup file is exactly that: nobody else has your
/// shop's records. Having just produced it, you get to set a new password.
///
/// Skippable on purpose. Most restores are a new phone rather than a forgotten
/// password, and those people already know what they type.
class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key, required this.username});

  final String username;

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : () => context.go('/'),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
          children: [
            SelloraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    icon: Icons.lock_outline,
                    title: 'Signed in as @${widget.username}',
                  ),
                  Gap.h12,
                  Text(
                    'Your records are back. If you came here because you could '
                    'not remember your password, set a new one now. If you '
                    'still know it, skip this — nothing changes.',
                    style: context.text.bodyMedium,
                  ),
                  Gap.h16,
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'At least 6 characters'
                        : null,
                  ),
                  Gap.h12,
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password'),
                    validator: (v) =>
                        v == _password.text ? null : 'Passwords do not match',
                    onFieldSubmitted: (_) => _save(),
                  ),
                  Gap.h16,
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const ButtonSpinner()
                        : const Text('Save new password'),
                  ),
                ],
              ),
            ),
            Gap.h16,
            Text(
              'Your old password stops working straight away. This phone is '
              'the only place either one is stored.',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setPasswordAfterRestore(_password.text);

      if (!mounted) return;
      context.go('/');
      showToast(context, 'Password changed. Use the new one next time.');
    } on AuthException catch (e) {
      if (mounted) showToast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showToast(context, 'Could not save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
