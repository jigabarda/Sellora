import 'package:flutter/material.dart';

import 'brand_palette.dart';

/// Design tokens for the app, delivered through the theme so every surface
/// adapts to light and dark automatically.
///
/// Screens must read colours from `context.t` rather than hardcoding hex
/// literals — a literal cannot respond to the theme, which is what left the
/// app with two incompatible looks before.
@immutable
class SelloraTokens extends ThemeExtension<SelloraTokens> {
  const SelloraTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
  });

  /// Page background.
  final Color canvas;

  /// Cards and sheets sitting on [canvas].
  final Color surface;

  /// Inset areas: search fields, chips, table stripes.
  final Color surfaceAlt;

  final Color line;
  final Color lineStrong;

  /// Primary text.
  final Color ink;

  /// Secondary text.
  final Color muted;

  /// Tertiary text, placeholders, disabled.
  final Color faint;

  /// Brand accent, chosen by the user in Settings. The value baked into
  /// [light] and [dark] is only the default; [withPalette] replaces it.
  ///
  /// A palette may well land on a green or a red, which is why nothing in the
  /// app is allowed to signal success or failure through the accent alone.
  final Color accent;

  /// Tinted background for accent chips and selected rows. Derived from
  /// [accent] rather than stored per palette.
  final Color accentSoft;

  /// Text and icons drawn on top of [accent].
  final Color onAccent;

  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;

  static const light = SelloraTokens(
    canvas: Color(0xFFFBFBFA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF4F4F3),
    line: Color(0xFFE7E6E3),
    lineStrong: Color(0xFFD4D3CF),
    ink: Color(0xFF14140F),
    muted: Color(0xFF5C5B55),
    faint: Color(0xFF8E8D86),
    accent: Color(0xFF4F46E5),
    accentSoft: Color(0xFFEEEDFC),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF0F8A54),
    successSoft: Color(0xFFE3F5EC),
    danger: Color(0xFFC62D30),
    dangerSoft: Color(0xFFFBEAEA),
    warning: Color(0xFFB2711A),
    warningSoft: Color(0xFFFDF1E1),
  );

  static const dark = SelloraTokens(
    canvas: Color(0xFF101011),
    surface: Color(0xFF1A1A1C),
    surfaceAlt: Color(0xFF232326),
    line: Color(0xFF2E2E32),
    lineStrong: Color(0xFF3F3F45),
    ink: Color(0xFFF3F2EF),
    muted: Color(0xFFA6A5A0),
    faint: Color(0xFF74736E),
    accent: Color(0xFF8B85FF),
    accentSoft: Color(0xFF25234A),
    onAccent: Color(0xFF14140F),
    success: Color(0xFF3ECF8E),
    successSoft: Color(0xFF12301F),
    danger: Color(0xFFFF6B6B),
    dangerSoft: Color(0xFF3A1A1C),
    warning: Color(0xFFE0A05A),
    warningSoft: Color(0xFF33240F),
  );

  /// Recolours the accent trio for the user's branding choice.
  ///
  /// `accentSoft` and `onAccent` are computed instead of stored per palette so
  /// adding a palette only ever means picking two colours. The soft tint is
  /// composited over [surface] because that is what it actually sits on.
  SelloraTokens withPalette(BrandPalette palette, Brightness brightness) {
    final accent = palette.accentFor(brightness);
    final isDark = brightness == Brightness.dark;
    return copyWith(
      accent: accent,
      accentSoft: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.22 : 0.12),
        surface,
      ),
      onAccent: onColor(accent),
    );
  }

  /// Ink or white — whichever is actually more readable on [background].
  ///
  /// This compares real WCAG contrast ratios rather than testing luminance
  /// against a threshold. A threshold looks equivalent and is not: at the
  /// midtones where most brand colours live it picks white when dark text is
  /// twice as readable. Dark indigo scores 3.04:1 against white and 6.07:1
  /// against ink, and seven of the shipped accents were getting the losing
  /// choice before this compared the two directly.
  static Color onColor(Color background) {
    const ink = Color(0xFF14140F);
    const white = Color(0xFFFFFFFF);
    return _contrast(background, ink) > _contrast(background, white)
        ? ink
        : white;
  }

  /// WCAG relative-contrast ratio, from 1 (identical) to 21 (black on white).
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  @override
  SelloraTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceAlt,
    Color? line,
    Color? lineStrong,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? accentSoft,
    Color? onAccent,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
  }) {
    return SelloraTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  SelloraTokens lerp(ThemeExtension<SelloraTokens>? other, double t) {
    if (other is! SelloraTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SelloraTokens(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      line: c(line, other.line),
      lineStrong: c(lineStrong, other.lineStrong),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccent: c(onAccent, other.onAccent),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
    );
  }
}

/// Spacing scale. Sticking to these keeps rhythm consistent across screens.
class Gap {
  const Gap._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  static const h4 = SizedBox(height: xs);
  static const h8 = SizedBox(height: sm);
  static const h12 = SizedBox(height: md);
  static const h16 = SizedBox(height: lg);
  static const h24 = SizedBox(height: xl);
  static const h32 = SizedBox(height: xxl);

  static const w4 = SizedBox(width: xs);
  static const w8 = SizedBox(width: sm);
  static const w12 = SizedBox(width: md);
  static const w16 = SizedBox(width: lg);
}

/// Corner radii. One step per surface size keeps the shape language tight.
class Radii {
  const Radii._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

extension SelloraThemeContext on BuildContext {
  /// Design tokens for the active theme.
  SelloraTokens get t =>
      Theme.of(this).extension<SelloraTokens>() ?? SelloraTokens.light;

  TextTheme get text => Theme.of(this).textTheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
