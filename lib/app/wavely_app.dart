import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/app/app_providers.dart';
import 'package:wavely/app/root_messenger.dart';
import 'package:wavely/app/router.dart';
import 'package:wavely/app/splash.dart';
import 'package:wavely/app/theme_provider.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/l10n/app_localizations.dart';

/// Root widget: wires the canonical settings (theme mode + accent + locale)
/// into the MaterialApp and the go_router configuration.
///
/// Phase 11: localizationsDelegates include the generated
/// [AppLocalizations] so Persian (فارسی) is a first-class locale with full
/// RTL mirroring.
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
      // BUG-9: lets non-UI layers (parental preload hook) show toasts.
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: ref.watch(routerProvider),
      // Phase 12: branded splash gate (fades the logo in/out once).
      builder: (context, child) => SplashGate(child: child ?? const SizedBox.shrink()),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
