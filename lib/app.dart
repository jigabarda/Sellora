import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/sellora_theme.dart';
import 'core/theme_controller.dart';
import 'router.dart';

class SelloraMobileApp extends ConsumerWidget {
  const SelloraMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Sellora',
      theme: buildSelloraTheme(Brightness.light),
      darkTheme: buildSelloraTheme(Brightness.dark),
      themeMode: ref.watch(themeControllerProvider),
      routerConfig: router,
      builder: (context, child) {
        // Business screens are dense with numbers, and runaway system font
        // scaling breaks the layouts outright. Allow growth, but bound it.
        final scaler = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        );
      },
    );
  }
}
