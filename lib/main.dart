import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/brand_palette.dart';
import 'core/theme_controller.dart';
import 'data/auth/auth_controller.dart';
import 'data/db/sellora_database.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final database = await SelloraDatabase.open();
  final auth = AuthController(database, prefs);
  await auth.restoreSession();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) => database),
        authControllerProvider.overrideWith((ref) => auth),
        themeControllerProvider.overrideWith((ref) => ThemeController(prefs)),
        brandPaletteProvider
            .overrideWith((ref) => BrandPaletteController(prefs)),
      ],
      child: const SelloraMobileApp(),
    ),
  );
}
