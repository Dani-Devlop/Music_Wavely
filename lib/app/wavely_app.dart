import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/app/app_providers.dart';
import 'package:wavely/app/router.dart';
import 'package:wavely/app/theme_provider.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

/// Root widget: wires the canonical settings (theme mode + accent) into the
/// MaterialApp and the go_router configuration.
class WavelyApp extends ConsumerWidget {
  /// Creates the app.
  const WavelyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePair = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Wavely',
      theme: themePair.light,
      darkTheme: themePair.dark,
      themeMode: settings.themeMode,
      // Zero theme animation avoids a flash when switching mode/accent.
      themeAnimationDuration: Duration.zero,
      routerConfig: ref.watch(routerProvider),
      locale: locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const <Locale>[Locale('en')],
      debugShowCheckedModeBanner: false,
    );
  }
}
