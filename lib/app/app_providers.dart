import 'dart:ui' show Locale;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

part 'app_providers.g.dart';

/// App locale (Phase 11): 'system' resolves through the OS (Android 13+
/// per-app language), otherwise the explicit 'en' / 'fa' selection wins.
@Riverpod(keepAlive: true)
Locale? locale(Ref ref) {
  final code = ref.watch(settingsProvider).localeCode;
  return switch (code) {
    'en' => const Locale('en'),
    'fa' => const Locale('fa'),
    _ => null,
  };
}

/// Package metadata for the About section; the settings screen renders a
/// fallback when the platform lookup fails (e.g. tests).
@Riverpod(keepAlive: true)
Future<PackageInfo> packageInfo(Ref ref) =>
    PackageInfo.fromPlatform();
