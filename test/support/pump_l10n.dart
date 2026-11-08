/// Phase 11 — shared localization wiring for every widget-test harness.
///
/// All five harness families (app `pumpWavelyApp`, design-system
/// `pumpThemed`, golden screenshots, the two E2E harnesses and the
/// per-feature screen pumps) mount their widgets inside a `MaterialApp`
/// built by hand. Without `localizationsDelegates` + `supportedLocales`
/// any screen that reaches for `AppLocalizations.of(context)` throws
/// "No AppLocalizations found" under `flutter test`.
///
/// Import this file and spread [l10nDelegates] / [l10nSupportedLocales]
/// into the harness `MaterialApp`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: l10nDelegates,
///   supportedLocales: l10nSupportedLocales,
///   ...
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:wavely/l10n/app_localizations.dart';

/// The exact delegate set the real app mounts (`WavelyApp`): generated
/// `AppLocalizations` + Material/Cupertino/Widgets defaults.
const List<LocalizationsDelegate<dynamic>> l10nDelegates =
    AppLocalizations.localizationsDelegates;

/// The locales the app ships (English template + complete Persian).
const List<Locale> l10nSupportedLocales = AppLocalizations.supportedLocales;

/// Localized [MaterialApp] pre-configured with the app delegates.
///
/// Used by harnesses that construct bare MaterialApps; keeps the two
/// required arguments from drifting apart across the suite.
MaterialApp l10nMaterialApp({
  Key? key,
  Locale? locale,
  ThemeData? theme,
  bool debugShowCheckedModeBanner = true,
  Widget? home,
  RouteFactory? onGenerateRoute,
}) {
  return MaterialApp(
    key: key,
    locale: locale,
    theme: theme,
    debugShowCheckedModeBanner: debugShowCheckedModeBanner,
    localizationsDelegates: l10nDelegates,
    supportedLocales: l10nSupportedLocales,
    home: home,
    onGenerateRoute: onGenerateRoute,
  );
}
