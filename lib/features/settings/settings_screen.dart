import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/business_types.dart';
import '../../core/brand_palette.dart';
import '../../core/sellora_ui.dart';
import '../../core/theme_controller.dart';
import '../../data/auth/auth_controller.dart';
import '../../data/repositories/business_repository.dart';
import '../../providers.dart';

/// Local counterpart to the web app's `/settings` page.
///
/// Team members and role permissions are deliberately absent: the local
/// `users` table holds device accounts, not members of a shared business, so
/// there is nobody to invite and no server to enforce a role against.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.businessId});

  final String businessId;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _accountKey = GlobalKey<FormState>();
  final _businessKey = GlobalKey<FormState>();

  final _fullName = TextEditingController();
  final _bizName = TextEditingController();
  final _bizAddress = TextEditingController();
  final _bizPhone = TextEditingController();
  String? _bizType;

  // The forms are seeded from async reads, but only on the first delivery.
  // Re-seeding on every rebuild would wipe whatever the user is typing.
  bool _seededAccount = false;
  bool _seededBusiness = false;

  bool _savingAccount = false;
  bool _savingBusiness = false;

  @override
  void dispose() {
    _fullName.dispose();
    _bizName.dispose();
    _bizAddress.dispose();
    _bizPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final businessAsync = ref.watch(businessProvider(widget.businessId));

    final user = userAsync.valueOrNull;
    if (user != null && !_seededAccount) {
      _fullName.text = user.name;
      _seededAccount = true;
    }

    final business = businessAsync.valueOrNull;
    if (business != null && !_seededBusiness) {
      _bizName.text = business.name;
      _bizAddress.text = business.address;
      _bizPhone.text = business.phone;
      _bizType = business.type;
      _seededBusiness = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: userAsync.isLoading || businessAsync.isLoading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
              children: [
                if (user != null) ...[_accountCard(user), Gap.h12],
                if (business != null) ...[_businessCard(), Gap.h12],
                _appearanceCard(),
                Gap.h12,
                _dataCard(),
                if (business != null) ...[Gap.h12, _dangerCard(business)],
              ],
            ),
    );
  }

  // --- Account -------------------------------------------------------------

  Widget _accountCard(LocalUser user) {
    return SelloraCard(
      child: Form(
        key: _accountKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              icon: Icons.person_outline,
              title: 'Account',
              subtitle: 'Your personal details',
            ),
            Gap.h16,
            TextFormField(
              initialValue: user.username,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText:
                    'Identifies this local account and cannot be changed.',
              ),
            ),
            Gap.h12,
            TextFormField(
              controller: _fullName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            Gap.h16,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _savingAccount ? null : _openPasswordDialog,
                    icon: const Icon(Icons.lock_outline, size: 17),
                    label: const Text('Password'),
                  ),
                ),
                Gap.w12,
                Expanded(
                  child: FilledButton(
                    onPressed: _savingAccount ? null : _saveAccount,
                    child: _savingAccount
                        ? const ButtonSpinner()
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAccount() async {
    if (!_accountKey.currentState!.validate()) return;
    setState(() => _savingAccount = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateName(_fullName.text);
      ref.invalidate(currentUserProvider);
      if (mounted) showToast(context, 'Profile updated');
    } on AuthException catch (e) {
      if (mounted) showToast(context, e.message, isError: true);
    } catch (e) {
      if (mounted) showToast(context, 'Could not save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingAccount = false);
    }
  }

  Future<void> _openPasswordDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && mounted) showToast(context, 'Password changed');
  }

  // --- Business ------------------------------------------------------------

  Widget _businessCard() {
    return SelloraCard(
      child: Form(
        key: _businessKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              icon: Icons.storefront_outlined,
              title: 'Business profile',
              subtitle: 'Shown on this device only',
            ),
            Gap.h16,
            TextFormField(
              controller: _bizName,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter a business name'
                  : null,
            ),
            Gap.h12,
            DropdownButtonFormField<String>(
              initialValue: _bizType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Business type'),
              items: withStoredBusinessType(_bizType)
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(growable: false),
              onChanged: (v) => setState(() => _bizType = v),
              validator: (v) => v == null ? 'Select a business type' : null,
            ),
            Gap.h12,
            TextFormField(
              controller: _bizAddress,
              maxLines: 2,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            Gap.h12,
            TextFormField(
              controller: _bizPhone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Phone',
                hintText: '09XX-XXX-XXXX',
              ),
            ),
            Gap.h16,
            FilledButton(
              onPressed: _savingBusiness ? null : _saveBusiness,
              child: _savingBusiness
                  ? const ButtonSpinner()
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveBusiness() async {
    if (!_businessKey.currentState!.validate()) return;
    setState(() => _savingBusiness = true);
    try {
      await ref.read(businessRepositoryProvider).updateProfile(
            id: widget.businessId,
            name: _bizName.text.trim(),
            type: _bizType!,
            address: _bizAddress.text.trim(),
            phone: _bizPhone.text.trim(),
          );
      // The shell header and the business list both render the name.
      ref.invalidate(businessProvider(widget.businessId));
      ref.invalidate(businessesProvider);
      if (mounted) showToast(context, 'Business updated');
    } catch (e) {
      if (mounted) showToast(context, 'Could not save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingBusiness = false);
    }
  }

  // --- Appearance ----------------------------------------------------------

  Widget _appearanceCard() {
    final mode = ref.watch(themeControllerProvider);

    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: Icons.dark_mode_outlined,
            title: 'Appearance',
            subtitle: 'How Sellora looks on this device',
          ),
          Gap.h16,
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Auto'),
                icon: Icon(Icons.brightness_auto_outlined, size: 17),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined, size: 17),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined, size: 17),
              ),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(themeControllerProvider.notifier).set(s.first),
          ),
          Gap.h24,
          Text('Brand colour', style: context.text.titleSmall),
          Gap.h4,
          Text(
            'Used for highlights, links and the active tab.',
            style: context.text.bodySmall,
          ),
          Gap.h12,
          _PalettePicker(
            selected: ref.watch(brandPaletteProvider),
            onSelected: (p) {
              // The whole app recolours on this tap. A confirming tick makes
              // that feel chosen rather than accidental.
              HapticFeedback.selectionClick();
              ref.read(brandPaletteProvider.notifier).set(p);
            },
          ),
        ],
      ),
    );
  }

  // --- Data ----------------------------------------------------------------

  Widget _dataCard() {
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: Icons.save_alt_outlined,
            title: 'Data',
            subtitle: 'Your records live only on this device',
          ),
          Gap.h12,
          ListTile(
            onTap: () => context.push('/backup'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_outlined, size: 20),
            title: Text(
              'Backup & restore',
              style:
                  context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Export every business to a file, or restore from one',
              style: context.text.bodySmall,
            ),
            trailing:
                Icon(Icons.chevron_right, size: 20, color: context.t.faint),
          ),
        ],
      ),
    );
  }

  // --- Danger zone ---------------------------------------------------------

  Widget _dangerCard(Business business) {
    final t = context.t;
    return SelloraCard(
      borderColor: t.danger.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: Icons.warning_amber_rounded,
            title: 'Danger zone',
            subtitle: 'Irreversible actions for this business',
            tone: t.danger,
          ),
          Gap.h16,
          Text(
            'Deleting ${business.name} removes its products, sales, customers, '
            'expenses, refunds, and stock history. Export a backup first if you '
            'may need these records.',
            style: context.text.bodyMedium,
          ),
          Gap.h16,
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(business),
            style: dangerButtonStyle(context),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('Delete business'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Business business) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete business',
      message: 'This permanently deletes ${business.name} and all of its data. '
          'This cannot be undone.',
      confirmLabel: 'Delete forever',
      confirmationWord: business.name,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(businessRepositoryProvider).delete(business.id);
      ref.invalidate(businessesProvider);
      if (!mounted) return;
      showToast(context, '${business.name} deleted');
      // Every provider below this route is keyed on a business that no longer
      // exists, so leave the whole branch rather than popping one screen.
      context.go('/');
    } catch (e) {
      if (mounted) showToast(context, 'Could not delete: $e', isError: true);
    }
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password'),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your current password'
                    : null,
              ),
              Gap.h12,
              TextFormField(
                controller: _next,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  hintText: 'At least 6 characters',
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? 'At least 6 characters'
                    : null,
              ),
              Gap.h12,
              TextFormField(
                controller: _confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm password'),
                validator: (v) =>
                    v != _next.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ...[
                Gap.h12,
                Text(
                  _error!,
                  style:
                      context.text.bodySmall?.copyWith(color: context.t.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const ButtonSpinner() : const Text('Change'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not change password: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Swatch grid for choosing the brand accent.
///
/// Each swatch previews the colour as it will appear in the *current* theme,
/// not a single canonical version — picking "Amber" in dark mode should show
/// the lighter cut the app will actually use, or the choice looks wrong the
/// moment it applies.
class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.selected, required this.onSelected});

  final BrandPalette selected;
  final ValueChanged<BrandPalette> onSelected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            for (final palette in BrandPalette.values)
              _Swatch(
                palette: palette,
                colour: palette.accentFor(brightness),
                isSelected: palette == selected,
                onTap: () => onSelected(palette),
              ),
          ],
        ),
        Gap.h12,
        // The grid alone cannot say which swatch is which, and a tooltip needs
        // a long-press nobody will discover. Naming the current choice costs
        // one line and removes the guesswork.
        Text(
          selected.label,
          style: context.text.labelMedium?.copyWith(color: context.t.ink),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.palette,
    required this.colour,
    required this.isSelected,
    required this.onTap,
  });

  final BrandPalette palette;
  final Color colour;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Semantics(
      button: true,
      selected: isSelected,
      label: palette.label,
      child: Tooltip(
        message: palette.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colour,
              shape: BoxShape.circle,
              // The ring sits outside the fill so the colour itself is never
              // clipped, and it uses the canvas rather than a fixed white so
              // it reads as a gap in both themes.
              border: Border.all(
                color: isSelected ? t.ink : t.line,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 18,
                    // Same contrast rule the theme uses for text on the
                    // accent, so the tick never disagrees with the button it
                    // is previewing.
                    color: SelloraTokens.onColor(colour),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
