/// The composition root.
///
/// The only place that both constructs things and knows about Flutter. Every
/// other file either describes the domain (and lives in `wardrobe_core`) or
/// asks a provider for what it needs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/settings.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Settings are read before the first frame rather than awaited inside a
  // provider, so no screen has to render a spinner while waiting to find out
  // where the backend is.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
      ],
      child: const WashingAdviceApp(),
    ),
  );
}

class WashingAdviceApp extends StatelessWidget {
  const WashingAdviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Washing Advice',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Follows the system. A laundry app is used in a utility room at night
      // as often as in daylight.
      themeMode: ThemeMode.system,
      routerConfig: buildRouter(),
    );
  }
}
