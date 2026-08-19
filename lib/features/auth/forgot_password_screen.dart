import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/auth/auth_controller.dart';
import '../../providers.dart';

/// Getting back into an account whose password is gone.
///
/// There is no link to email and no server to send one from, so recovery here
/// means presenting something the owner kept: a recovery code, or the backup
/// file itself. Both are offered, because most accounts will have one or the
/// other rather than both.
///
/// Nothing here deletes anything. A forgotten password costs the password and
/// nothing else — the sales, the products and the businesses are not involved.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgotten password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
          children: [
            SelloraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    icon: Icons.vpn_key_outlined,
                    title: 'Use your recovery code',
                  ),
                  Gap.h12,
                  Text(
                    'The code you were shown when you made it. Your businesses '
                    'and sales are not touched — only the password changes.',
                    style: context.text.bodyMedium,
                  ),
                  Gap.h16,
                  TextFormField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixText: '@',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your username'
                        : null,
                  ),
                  Gap.h12,
                  TextFormField(
                    controller: _code,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Recovery code',
                      hintText: 'ABCD-EFGH-JKMN',
                    ),
                    validator: (v) => (v == null ||
                            AuthController.normalizeRecoveryCode(v).length < 12)
                        ? 'Enter the full code'
                        : null,
                  ),
                  Gap.h12,
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
                    onFieldSubmitted: (_) => _reset(),
                  ),
                  Gap.h16,
                  FilledButton(
                    onPressed: _busy ? null : _reset,
                    child: _busy
                        ? const ButtonSpinner()
                        : const Text('Set new password'),
                  ),
                ],
              ),
            ),
            Gap.h12,
            SelloraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    icon: Icons.settings_backup_restore_outlined,
                    title: 'No code?',
                  ),
                  Gap.h12,
                  Text(
                    'A backup file works too. Restoring one signs you in and '
                    'lets you set a new password.',
                    style: context.text.bodyMedium,
                  ),
                  Gap.h16,
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => context.push('/restore'),
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Restore from a backup file'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reset() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      final replacement = await ref
          .read(authControllerProvider.notifier)
          .resetPasswordWithRecoveryCode(
            username: _username.text,
            code: _code.text,
            newPassword: _password.text,
          );

      // Signed in straight away rather than sent back to a form: the password
      // was just set on this screen, so asking for it again is theatre.
      await ref.read(authControllerProvider.notifier).login(
            username: _username.text,
            password: _password.text,
          );

      if (!mounted) return;
      // The spent code is gone, so its replacement has to be shown now or the
      // owner is left with no way back the next time.
      context.go('/recovery-code', extra: replacement);
    } on AuthException catch (e) {
      if (mounted) showToast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showToast(context, 'Could not reset: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
