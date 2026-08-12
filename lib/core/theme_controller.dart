import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefThemeMode = 'theme_mode';

/// Persists the user's light/dark choice so the app does not flash back to
/// system default on every launch.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _read(SharedPreferences prefs) {
    return switch (prefs.getString(_prefThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_prefThemeMode, mode.name);
  }
}

/// Overridden in `main.dart` once SharedPreferences is open.
final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>(
  (ref) => throw StateError(
      'themeControllerProvider must be overridden in ProviderScope'),
);
