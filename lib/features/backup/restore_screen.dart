import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/sellora_ui.dart';
import '../../data/backup/backup_service.dart';
import '../../providers.dart';

/// Recovering an account from a backup file, before there is an account.
///
/// The in-app restore assumes you are already signed in and replacing your own
/// data. That is the wrong shape for the case this exists for: the phone is
/// gone, the new one is empty, and the only thing left is a file. Reaching the
/// old screen would mean registering a throwaway account first, restoring into
/// it, and then working out for yourself that you have to sign out and sign
/// back in as someone else — which is not a recovery flow, it is a puzzle.
///
/// So this sits outside the login wall and finishes the job: it reads the file,
/// says whose it is and what is in it, restores, and signs that account in.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  bool _busy = false;

  /// The file, held between picking it and confirming it, so the owner is not
  /// made to find it a second time after reading the preview.
  String? _raw;
  BackupSummary? _summary;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore from backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
        children: [
          SelloraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  icon: Icons.settings_backup_restore_outlined,
                  title: 'Bring back your records',
                ),
                Gap.h12,
                Text(
                  'Pick the backup file you saved. Your account comes back with '
                  'it — same username and password — along with every business, '
                  'product and sale it holds.',
                  style: context.text.bodyMedium,
                ),
                Gap.h16,
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(
                    summary == null ? 'Choose backup file' : 'Choose another',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            Gap.h12,
            SelloraCard(
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: t.danger, size: 20),
                  Gap.w12,
                  Expanded(
                    child: Text(
                      _error!,
                      style: context.text.bodyMedium?.copyWith(color: t.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (summary != null) ...[
            Gap.h12,
            SelloraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    icon: Icons.person_outline,
                    title: '@${summary.username}',
                  ),
                  Gap.h4,
                  Text(
                    'Saved ${formatTimestamp(summary.exportedAt)}',
                    style: context.text.bodySmall,
                  ),
                  Gap.h12,
                  DetailRow(
                      label: 'Businesses', value: '${summary.businesses}'),
                  DetailRow(label: 'Products', value: '${summary.products}'),
                  DetailRow(label: 'Sales', value: '${summary.sales}'),
                  DetailRow(label: 'Customers', value: '${summary.customers}'),
                  Gap.h16,
                  FilledButton(
                    onPressed: _busy ? null : _restore,
                    child: _busy
                        ? const ButtonSpinner()
                        : Text('Restore and sign in as @${summary.username}'),
                  ),
                ],
              ),
            ),
          ],
          Gap.h16,
          Text(
            'Restoring replaces whatever this account already has on this '
            'phone. Nothing else on the device is touched.',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    const typeGroup = XTypeGroup(
      label: 'Sellora backup',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    );

    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await picked.readAsString();
      // Inspected before anything is written, so a wrong file is a sentence on
      // screen rather than a half-finished restore.
      final summary = await ref.read(backupServiceProvider).inspect(raw);
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _summary = summary;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _raw = null;
          _summary = null;
          _error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final raw = _raw;
    if (raw == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final userId = await ref.read(backupServiceProvider).restore(raw);
      await ref
          .read(authControllerProvider.notifier)
          .adoptRestoredSession(userId);

      if (!mounted) return;
      // Not back to a login form — the whole point is that the person doing
      // this has already lost enough steps. Straight on to the offer of a new
      // password instead, since a forgotten one is half the reason to be here
      // and the file has just proved the account is theirs.
      context.go('/new-password', extra: _summary?.username);
      showToast(context, 'Your records are back.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
