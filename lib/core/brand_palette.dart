import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefBrandPalette = 'brand_palette';

/// Accent colours a business can brand the app with.
///
/// Only the accent varies. Canvas, ink and the success/danger semantics stay
/// fixed across every palette — a business choosing "Rose" still needs a red
/// that unambiguously reads as an error, and letting the brand colour move
/// those would make the two indistinguishable.
///
/// Each entry carries a hand-picked pair rather than one colour lightened
/// programmatically: a hue that reads well on a near-white canvas is usually
/// too dark and too saturated against a near-black one.
enum BrandPalette {
  indigo('Indigo', Color(0xFF4F46E5), Color(0xFF8B85FF)),
  violet('Violet', Color(0xFF7C3AED), Color(0xFFA78BFA)),
  blue('Blue', Color(0xFF2563EB), Color(0xFF60A5FA)),
  teal('Teal', Color(0xFF0D9488), Color(0xFF2DD4BF)),
  emerald('Emerald', Color(0xFF059669), Color(0xFF34D399)),
  amber('Amber', Color(0xFFD97706), Color(0xFFFBBF24)),
  rose('Rose', Color(0xFFE11D48), Color(0xFFFB7185)),
  graphite('Graphite', Color(0xFF3F3F46), Color(0xFFA1A1AA));

  const BrandPalette(this.label, this.lightAccent, this.darkAccent);

  /// Shown in the Settings picker.
  final String label;

  final Color lightAccent;
  final Color darkAccent;

  static const fallback = BrandPalette.indigo;

  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  /// Resolves a stored name, falling back when the value is absent or came
  /// from a build that had a palette this one no longer ships.
  static BrandPalette fromName(String? name) {
    for (final p in BrandPalette.values) {
      if (p.name == name) return p;
    }
    return fallback;
  }
}

/// Persists the branding choice so it survives a restart.
class BrandPaletteController extends StateNotifier<BrandPalette> {
  BrandPaletteController(this._prefs)
      : super(BrandPalette.fromName(_prefs.getString(_prefBrandPalette)));

  final SharedPreferences _prefs;

  Future<void> set(BrandPalette palette) async {
    state = palette;
    await _prefs.setString(_prefBrandPalette, palette.name);
  }
}

/// Overridden in `main.dart` once SharedPreferences is open.
final brandPaletteProvider =
    StateNotifierProvider<BrandPaletteController, BrandPalette>(
  (ref) => throw StateError(
      'brandPaletteProvider must be overridden in ProviderScope'),
);
