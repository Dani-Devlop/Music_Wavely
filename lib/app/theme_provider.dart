import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/design_system/themes/app_theme.dart';
import 'package:wavely/design_system/tokens/colors.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/domain/settings.dart';

part 'theme_provider.g.dart';

/// Both [ThemeData]s for the current accent, built once per settings change.
class ThemePair {
  /// Creates the pair from the design-system factories.
  const ThemePair({required this.light, required this.dark});

  final ThemeData light;

  final ThemeData dark;
}

/// Rebuilds the theme pair whenever the canonical [AppSettings] accent
/// changes. Registered [WavelySemanticColors] extension is guaranteed by the
/// design-system factories.
@Riverpod(keepAlive: true)
ThemePair theme(Ref ref) {
  final settings = ref.watch(settingsProvider);
  final accent = settings.accent.toWavelyAccent();
  return ThemePair(
    light: WavelyThemes.light(accent),
    dark: WavelyThemes.dark(accent),
  );
}
