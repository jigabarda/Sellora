import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sellora_tokens.dart';

/// Serif is reserved for the "Sellora" wordmark. Everything else uses the
/// platform UI font, which is what makes the app feel native rather than
/// like a themed website.
const kBrandFontFamily = 'serif';

ThemeData buildSelloraTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final t = isDark ? SelloraTokens.dark : SelloraTokens.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: t.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.accent,
      brightness: brightness,
    ).copyWith(
      surface: t.surface,
      primary: t.accent,
      onPrimary: t.onAccent,
      error: t.danger,
      outline: t.line,
    ),
    extensions: [t],
  );

  final text = _textTheme(base.textTheme, t);

  return base.copyWith(
    textTheme: text,
    primaryTextTheme: text,
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: t.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.muted,
      textColor: t.ink,
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle: text.bodySmall?.copyWith(color: t.muted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.surface,
      labelStyle: text.bodyMedium?.copyWith(color: t.muted),
      floatingLabelStyle: text.bodySmall?.copyWith(color: t.accent),
      hintStyle: text.bodyMedium?.copyWith(color: t.faint),
      helperStyle: text.bodySmall?.copyWith(color: t.faint),
      errorStyle: text.bodySmall?.copyWith(color: t.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: _border(t.line),
      enabledBorder: _border(t.line),
      focusedBorder: _border(t.accent, width: 1.6),
      errorBorder: _border(t.danger),
      focusedErrorBorder: _border(t.danger, width: 1.6),
      disabledBorder: _border(t.line),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.ink,
        foregroundColor: t.canvas,
        disabledBackgroundColor: t.lineStrong,
        disabledForegroundColor: t.faint,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: t.lineStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        textStyle: text.labelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.ink,
      foregroundColor: t.canvas,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedTextStyle: text.labelLarge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.ink,
      contentTextStyle: text.bodyMedium?.copyWith(color: t.canvas),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      insetPadding: const EdgeInsets.all(Gap.lg),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      contentTextStyle: text.bodyMedium?.copyWith(color: t.muted),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: t.line),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: t.lineStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(t.onAccent),
      side: BorderSide(color: t.lineStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.surfaceAlt,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.lineStrong),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.surfaceAlt,
      circularTrackColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: t.line),
      ),
      textStyle: text.bodyMedium,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

OutlineInputBorder _border(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// A tighter scale than Material's default — business screens pack a lot of
/// numbers, so the steps between sizes need to stay small and deliberate.
TextTheme _textTheme(TextTheme base, SelloraTokens t) {
  TextStyle s(double size, FontWeight weight, {Color? color, double? height}) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color ?? t.ink,
      height: height,
      letterSpacing: size >= 24 ? -0.6 : (size >= 18 ? -0.3 : -0.1),
    );
  }

  return base.copyWith(
    displaySmall: s(30, FontWeight.w800, height: 1.15),
    headlineMedium: s(26, FontWeight.w800, height: 1.15),
    headlineSmall: s(22, FontWeight.w700, height: 1.2),
    titleLarge: s(19, FontWeight.w700, height: 1.25),
    titleMedium: s(16, FontWeight.w700, height: 1.3),
    titleSmall: s(14, FontWeight.w600, height: 1.3),
    bodyLarge: s(15, FontWeight.w500, height: 1.4),
    bodyMedium: s(14, FontWeight.w400, color: t.muted, height: 1.45),
    bodySmall: s(12.5, FontWeight.w400, color: t.muted, height: 1.4),
    labelLarge: s(14.5, FontWeight.w600),
    labelMedium: s(12.5, FontWeight.w600, color: t.muted),
    labelSmall: s(11, FontWeight.w600, color: t.faint),
  );
}
