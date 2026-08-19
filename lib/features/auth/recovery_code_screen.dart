import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';

/// Shows a recovery code once, and only once.
///
/// Only its hash is kept, so this screen is the single moment the code exists
/// anywhere readable. That is the point — a code the app could show again on
/// demand would be a code anyone holding the unlocked phone could take — but it
/// does mean the screen has to be blunt about it rather than polite.
class RecoveryCodeScreen extends ConsumerWidget {
  const RecoveryCodeScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your recovery code'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, 40),
        children: [
          SelloraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  icon: Icons.vpn_key_outlined,
                  title: 'Write this down',
                ),
                Gap.h12,
                Text(
                  'If you ever forget your password, this code is how you set '
                  'a new one. Keep it somewhere away from this phone — a '
                  'notebook, a wallet.',
                  style: context.text.bodyMedium,
                ),
                Gap.h16,
                Container(
                  padding: const EdgeInsets.symmetric(vertical: Gap.lg),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall?.copyWith(
                      color: t.accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Gap.h12,
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) showToast(context, 'Code copied');
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ),
          Gap.h12,
          SelloraCard(
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: t.warning, size: 20),
                Gap.w12,
                Expanded(
                  child: Text(
                    'This is the only time it will be shown. Sellora keeps no '
                    'readable copy, so nobody — including us — can look it up '
                    'for you later.',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Gap.h16,
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('I have written it down'),
          ),
        ],
      ),
    );
  }
}
