import 'dart:ui' show Locale;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_providers.g.dart';

/// App locale (single supported locale in Stage 1.1).
@Riverpod(keepAlive: true)
Locale locale(Ref ref) => const Locale('en');

/// Package metadata for the About section; the settings screen renders a
/// fallback when the platform lookup fails (e.g. tests).
@Riverpod(keepAlive: true)
Future<PackageInfo> packageInfo(Ref ref) =>
    PackageInfo.fromPlatform();
