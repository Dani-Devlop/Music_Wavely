import 'package:flutter/material.dart' show ThemeMode;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/design_system/tokens/colors.dart';

part 'settings.freezed.dart';

/// Accent choices surfaced in settings (design-system tokens stay canonical).
enum AccentColor { purple, green }

/// Maps a settings [AccentColor] onto the design-system accent tokens.
extension AccentColorX on AccentColor {
  WavelyAccent get toWavelyAccent => switch (this) {
        AccentColor.purple => WavelyAccent.purple,
        AccentColor.green => WavelyAccent.green,
      };
}

/// Tolerant parser for the persisted accent name; `null` on unknown input so
/// callers fall back to the default.
AccentColor? accentFromName(String? raw) => switch (raw) {
      'purple' => AccentColor.purple,
      'green' => AccentColor.green,
      _ => null,
    };

/// Tolerant parser for the persisted theme-mode name; `null` on unknown input
/// so callers fall back to the default.
ThemeMode? themeModeFromName(String? raw) => switch (raw) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };

/// Canonical user settings for the whole app (Task B of Stage 1.1).
///
/// Crossfade, gapless playback, never-play languages and playback speed are
/// persisted now but only consumed by later-stage engine features — in Stage
/// 1.1 they are state-only for the settings UI.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(AccentColor.purple) AccentColor accent,
    @Default(false) bool reduceTransparency,
    // --- Phase 10 (UI polish): AMOLED / adaptive accent / blur / radius ---
    /// Pure-black AMOLED surfaces (only meaningful in dark mode).
    @Default(false) bool amoled,
    /// Derive the accent seed from the current album art.
    @Default(false) bool adaptiveAccent,
    /// Last extracted adaptive accent (ARGB int; 0 = none).
    @Default(0) int adaptiveAccentValue,
    /// Backdrop blur multiplier (0..[maxBlurScale], 1 = design tokens).
    @Default(1.0) double blurScale,
    /// Corner radius multiplier (0.5..[maxRadiusScale], 1 = design tokens).
    @Default(1.0) double radiusScale,
    /// UI language: 'system' (per-app language / OS default), 'en' or 'fa'.
    @Default('system') String localeCode,
    @Default(0) double crossfadeSeconds,
    @Default(true) bool gaplessPlayback,
    @Default(true) bool resumeOnStart,
    @Default('{artist}/{album}/{title}') String storageTemplate,
    @Default(<String>[]) List<String> scanFolders,
    @Default(<String>[]) List<String> neverPlayLanguages,
    @Default(1.0) double playbackSpeed,
  }) = _AppSettings;
}

/// Bounds of the blur-strength slider (Phase 10): 0 disables blurs.
const double maxBlurScale = 2.0;

/// Bounds of the corner-radius slider (Phase 10).
const double minRadiusScale = 0.5;
const double maxRadiusScale = 2.0;
