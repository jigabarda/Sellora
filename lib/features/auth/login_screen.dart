import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';
import '../../data/auth/auth_controller.dart';
import '../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SelloraLockup(size: 24),
                    Gap.h24,
                    Text('Welcome back', style: context.text.headlineMedium),
                    Gap.h4,
                    Text(
                      'Sign in to the account stored on this device.',
                      style: context.text.bodyMedium,
                    ),
                    Gap.h24,
                    TextFormField(
                      controller: _username,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      // Usernames are stored lowercase, so leave the keyboard
                      // out of it rather than silently correcting the user.
                      textCapitalization: TextCapitalization.none,
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
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),
                    // Under the field it is about, where someone looks the
                    // moment the password they typed does not work. Quiet and
                    // right-aligned so it reads as a footnote to the field
                    // rather than competing with Sign in.
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push('/forgot-password'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: context.text.bodySmall,
                        ),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    Gap.h16,
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child:
                          _busy ? const ButtonSpinner() : const Text('Sign in'),
                    ),
                    Gap.h16,
                    // Wrap, not Row: at a large text scale the label and the
                    // button together exceed a phone's width.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text("Don't have an account?",
                            style: context.text.bodyMedium),
                        TextButton(
                          onPressed: () => context.push('/register'),
                          child: const Text('Sign up'),
                        ),
                      ],
                    ),
                    // Someone typing a password that no longer exists on a
                    // replacement phone needs this here, not buried behind an
                    // account they have not got yet.
                    TextButton.icon(
                      onPressed: () => context.push('/restore'),
                      icon: const Icon(Icons.settings_backup_restore_outlined,
                          size: 18),
                      label: const Text('Restore from a backup file'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            username: _username.text,
            password: _password.text,
          );
      if (!mounted) return;
      context.go('/');
    } on AuthException catch (e) {
      if (mounted) showToast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showToast(context, 'Login failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
