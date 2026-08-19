import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/sellora_ui.dart';
import '../../data/backup/backup_service.dart';
import '../../data/export/device_downloads.dart';
import '../../providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 40),
        children: [
          SelloraCard(
            color: t.warningSoft,
            borderColor: t.warning.withValues(alpha: 0.35),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 19, color: t.warning),
                Gap.w12,
                Expanded(
                  child: Text(
                    'Everything lives on this phone. Nothing is stored on a '
                    'server, so uninstalling the app or losing the device also '
                    'loses your records.',
                    style: context.text.bodyMedium?.copyWith(color: t.ink),
                  ),
                ),
              ],
            ),
          ),
          Gap.h16,
          _ActionCard(
            icon: Icons.upload_file_outlined,
            title: 'Export backup',
            body: 'Writes every business, product, sale, customer, expense and '
                'refund to a JSON file. Saving puts it in Downloads; sending '
                'hands it to an app you pick. It never leaves the phone on '
                'its own.',
            actionLabel: 'Save to device',
            actionIcon: Icons.download_outlined,
            onPressed: _busy ? null : _saveToDevice,
            secondaryLabel: 'Send a copy',
            secondaryIcon: Icons.ios_share,
            onSecondaryPressed: _busy ? null : _export,
          ),
          Gap.h12,
          _ActionCard(
            icon: Icons.settings_backup_restore_outlined,
            title: 'Restore from file',
            body: 'Replaces this account\'s data with the contents of a backup '
                'file. You will see exactly what the file contains before '
                'anything changes.',
            actionLabel: 'Choose backup file',
            actionIcon: Icons.folder_open_outlined,
            destructive: true,
            onPressed: _busy ? null : _restore,
          ),
          if (_busy) ...[
            Gap.h24,
            const LoadingView(),
          ],
        ],
      ),
    );
  }

  /// Puts the backup in Downloads, where the owner can find it again.
  ///
  /// An export that only offers a share sheet is not really an export: on some
  /// devices the sheet has no Files entry at all, and the whole point of a
  /// backup is having a file you can put somewhere safe yourself.
  ///
  /// Falls through to sharing on Android 9 and older, where writing to a public
  /// folder would mean asking for a storage permission this app does not hold.
  Future<void> _saveToDevice() async {
    final userId = ref.read(authControllerProvider).userId;
    if (userId == null) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final json = await service.exportToJson(userId);
      final saved = await ref.read(deviceDownloadsProvider).save(
            fileName: backupFileName(DateTime.now()),
            bytes: Uint8List.fromList(utf8.encode(json)),
            mimeType: 'application/json',
          );

      if (!mounted) return;
      showToast(context, 'Saved to Downloads as $saved');
    } on DownloadsUnsupported {
      if (!mounted) return;
      showToast(
          context,
          'This phone cannot save straight to Downloads — '
          'choose where to put it instead.');
      setState(() => _busy = false);
      await _export();
      return;
    } catch (e) {
      if (mounted) showToast(context, 'Export failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final userId = ref.read(authControllerProvider).userId;
    if (userId == null) return;

    setState(() => _busy = true);
    File? file;
    try {
      file = await ref
          .read(backupServiceProvider)
          .writeBackupFile(userId, DateTime.now());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: 'Sellora backup',
          text: 'Sellora backup — keep this file safe.',
        ),
      );
      if (!mounted) return;
      showToast(context, 'Backup created. Save it somewhere you control.');
    } catch (e) {
      if (mounted) showToast(context, 'Export failed: $e', isError: true);
    } finally {
      // The share sheet copies what it needs; the cache copy is disposable.
      try {
        await file?.delete();
      } on FileSystemException {
        // Nothing to clean up — cache is evictable anyway.
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    const typeGroup = XTypeGroup(
      label: 'Sellora backup',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    );

    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final raw = await picked.readAsString();
      final summary = await service.inspect(raw);

      if (!mounted) return;
      final confirmed = await _confirm(summary);
      if (confirmed != true || !mounted) return;

      await service.restore(raw);

      // Providers are keyed on ids that may no longer exist, and the session
      // may now belong to a different account. Signing out drops all of that
      // state; the router redirect sends us back to the welcome screen.
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      showToast(context, 'Restore complete. Sign in to continue.');
    } catch (e) {
      if (mounted) showToast(context, 'Restore failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(BackupSummary summary) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: dialogContext.t.danger),
        title: const Text('Replace your data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This backup belongs to @${summary.username} and contains:',
              style: dialogContext.text.bodyMedium,
            ),
            Gap.h12,
            DetailRow(label: 'Businesses', value: '${summary.businesses}'),
            DetailRow(label: 'Products', value: '${summary.products}'),
            DetailRow(label: 'Sales', value: '${summary.sales}'),
            DetailRow(label: 'Customers', value: '${summary.customers}'),
            Gap.h12,
            Text(
              'Everything currently on this account will be deleted and '
              'replaced. This cannot be undone.',
              style: dialogContext.text.bodyMedium?.copyWith(
                color: dialogContext.t.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: dangerButtonStyle(dialogContext, filled: true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionIcon,
    required this.onPressed,
    this.destructive = false,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondaryPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onPressed;
  final bool destructive;

  /// A quieter second way to do the same thing, shown under the main button.
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    return SelloraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: icon,
            title: title,
            tone: destructive ? context.t.danger : null,
          ),
          Gap.h12,
          Text(body, style: context.text.bodyMedium),
          Gap.h16,
          if (destructive)
            OutlinedButton.icon(
              onPressed: onPressed,
              style: dangerButtonStyle(context),
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            )
          else
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(actionIcon, size: 18),
              label: Text(actionLabel),
            ),
          if (secondaryLabel != null) ...[
            Gap.h8,
            OutlinedButton.icon(
              onPressed: onSecondaryPressed,
              icon: Icon(secondaryIcon, size: 18),
              label: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
