import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sellora_theme.dart';
import 'sellora_tokens.dart';

export 'sellora_tokens.dart'
    show SelloraTokens, Gap, Radii, SelloraThemeContext;

/// The "Sellora" wordmark.
class SelloraWordmark extends StatelessWidget {
  const SelloraWordmark({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Sellora',
      style: TextStyle(
        fontFamily: kBrandFontFamily,
        fontSize: size,
        // w800 is the heaviest cut bundled. Asking for w900 would make Flutter
        // synthesise a fake bold on top of it, which smears the letterforms.
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.1,
        color: color ?? context.t.ink,
      ),
    );
  }
}

/// Bordered surface. The app's only container primitive — no drop shadows,
/// so it reads the same in dark mode.
class SelloraCard extends StatelessWidget {
  const SelloraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final shape = BorderRadius.circular(Radii.lg);

    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        border: Border.all(color: borderColor ?? t.line),
        borderRadius: shape,
      ),
      child: child,
    );

    return Padding(
      padding: margin,
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: shape,
                child: body,
              ),
            ),
    );
  }
}

/// Icon tile + title + subtitle, used at the top of every card section.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Accent colour for the icon tile; defaults to the brand accent.
  final Color? tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = tone ?? t.accent;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: context.isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        Gap.w12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.titleSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(subtitle!, style: context.text.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

enum PillTone { neutral, accent, success, danger, warning }

/// Compact status label.
class SelloraPill extends StatelessWidget {
  const SelloraPill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (fg, bg) = switch (tone) {
      PillTone.neutral => (t.muted, t.surfaceAlt),
      PillTone.accent => (t.accent, t.accentSoft),
      PillTone.success => (t.success, t.successSoft),
      PillTone.danger => (t.danger, t.dangerSoft),
      PillTone.warning => (t.warning, t.warningSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Full-screen placeholder for "nothing here yet" and "no results".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Gap.xl,
          vertical: compact ? Gap.xl : 56,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surfaceAlt,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Icon(icon, size: 27, color: t.faint),
            ),
            Gap.h16,
            Text(title, style: context.text.titleMedium),
            Gap.h4,
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              Gap.h24,
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Makes a non-scrolling child scrollable so `RefreshIndicator` can still
/// drive it.
///
/// Pull-to-refresh silently does nothing when the indicator's child is not a
/// scrollable, which is easy to hit by returning an [EmptyState] straight out
/// of an `AsyncValue.when`.
class RefreshableFill extends StatelessWidget {
  const RefreshableFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

/// Consistent async states so no screen invents its own spinner or error text.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        height: 26,
        width: 26,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: '$error',
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// Spinner sized to sit inside a button without changing its height.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: color ?? context.t.canvas,
      ),
    );
  }
}

/// Label + value row, for summaries and confirmation dialogs.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Gap.w12,
          Text(
            value,
            textAlign: TextAlign.right,
            style:
                (emphasize ? context.text.titleSmall : context.text.bodyLarge)
                    ?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

/// Search box used by every list screen.
class SelloraSearchField extends StatelessWidget {
  const SelloraSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search...',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final hasText = controller.text.isNotEmpty;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: context.text.bodyLarge,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: t.surfaceAlt,
        prefixIcon: Icon(Icons.search, size: 20, color: t.faint),
        suffixIcon: hasText
            ? IconButton(
                icon: Icon(Icons.close, size: 18, color: t.muted),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: t.line),
        ),
      ),
    );
  }
}

/// Destructive-action button styling, applied consistently everywhere data
/// can be lost.
ButtonStyle dangerButtonStyle(BuildContext context, {bool filled = false}) {
  final t = context.t;
  return filled
      ? FilledButton.styleFrom(
          backgroundColor: t.danger,
          foregroundColor: Colors.white,
          disabledBackgroundColor: t.danger.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
        )
      : OutlinedButton.styleFrom(
          foregroundColor: t.danger,
          side: BorderSide(color: t.danger.withValues(alpha: 0.45)),
        );
}

/// Snackbars, with a single call site so tone and duration stay consistent.
void showToast(BuildContext context, String message, {bool isError = false}) {
  final t = context.t;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: isError ? t.danger : t.success,
            ),
            Gap.w8,
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
}

/// Confirmation for anything that destroys data.
///
/// [confirmationWord] adds a type-to-confirm field, for the cases where a
/// misplaced tap would be expensive.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String? confirmationWord,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _DestructiveDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      confirmationWord: confirmationWord,
    ),
  );
  if (result == true) await HapticFeedback.mediumImpact();
  return result ?? false;
}

class _DestructiveDialog extends StatefulWidget {
  const _DestructiveDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.confirmationWord,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String? confirmationWord;

  @override
  State<_DestructiveDialog> createState() => _DestructiveDialogState();
}

class _DestructiveDialogState extends State<_DestructiveDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.confirmationWord;
    final canConfirm = word == null || _typed.text.trim() == word;

    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: context.t.danger),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: context.text.bodyMedium),
          if (word != null) ...[
            Gap.h16,
            TextField(
              controller: _typed,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              style: context.text.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Type "$word" to confirm',
                hintText: word,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
          style: dangerButtonStyle(context, filled: true),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
