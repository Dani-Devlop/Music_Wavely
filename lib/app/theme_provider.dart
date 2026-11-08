import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/design_system/themes/app_theme.dart';
import 'package:wavely/design_system/tokens/blur.dart';
import 'package:wavely/design_system/tokens/colors.dart';
import 'package:wavely/design_system/tokens/radii.dart';
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

/// Resolves the effective accent token set: the named palette unless the
/// adaptive-accent mode is on and an album-art palette was extracted
/// (Phase 10).
AccentColors resolveAccentColors(AppSettings settings) {
  final adaptive = settings.adaptiveAccentValue;
  if (settings.adaptiveAccent && adaptive != 0) {
    return AccentColors.custom(Color(adaptive));
  }
  return settings.accent.toWavelyAccent.colors;
}

/// Rebuilds the theme pair whenever the canonical [AppSettings] accent
/// changes. Registered [WavelySemanticColors] extension is guaranteed by the
/// design-system factories.
///
/// Phase 10: also mirrors blur-strength / corner-radius settings into the
/// design-token runtime scales (single writer — theme changes rebuild the
/// tree through MaterialApp, so the token values are always current).
@Riverpod(keepAlive: true)
ThemePair theme(Ref ref) {
  final settings = ref.watch(settingsProvider);
  final colors = resolveAccentColors(settings);
  WavelyBlur.scale = settings.reduceTransparency
      ? 0
      : settings.blurScale;
  AppRadii.scale = settings.radiusScale;
  return ThemePair(
    light: WavelyThemes.light(colors),
    dark: WavelyThemes.dark(colors, amoled: settings.amoled),
  );
}
