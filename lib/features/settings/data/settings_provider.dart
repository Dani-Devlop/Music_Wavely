import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/features/settings/domain/settings.dart';

part 'settings_provider.g.dart';

/// Bootstrap-provided [SharedPreferences] instance.
///
/// The default throws: the composition root (`lib/app/bootstrap.dart` via
/// `buildOverrides`) replaces this provider with the real instance using
/// `overrideWithValue`, so every consumer reads the same snapshot.
@Riverpod(keepAlive: true)
SharedPreferences sharedPrefs(SharedPrefsRef ref) =>
    throw UnimplementedError('overridden with the bootstrap instance');

/// Loads, keeps and persists the canonical [AppSettings].
///
/// Every setter updates the state AND writes through to SharedPreferences
/// synchronously (fire-and-forget write, state is the source of truth for
/// the UI). Reads are tolerant: absent keys and garbage values fall back to
/// the [AppSettings] defaults.
///
/// Persistence contract: crossfade, gapless playback, never-play languages
/// and playback speed are persisted here already but only consumed by
/// later-stage engine features (state-only in Stage 1.1).
@Riverpod(keepAlive: true)
class SettingsNotifier extends _$SettingsNotifier {
  static const String _keyThemeMode =
      '${AppConstants.settingsKeyPrefix}themeMode';
  static const String _keyAccent = '${AppConstants.settingsKeyPrefix}accent';
  static const String _keyReduceTransparency =
      '${AppConstants.settingsKeyPrefix}reduceTransparency';
  static const String _keyCrossfadeSeconds =
      '${AppConstants.settingsKeyPrefix}crossfadeSeconds';
  static const String _keyGapless =
      '${AppConstants.settingsKeyPrefix}gapless';
  static const String _keyResumeOnStart =
      '${AppConstants.settingsKeyPrefix}resumeOnStart';
  static const String _keyStorageTemplate =
      '${AppConstants.settingsKeyPrefix}storageTemplate';
  static const String _keyScanFolders =
      '${AppConstants.settingsKeyPrefix}scanFolders';
  static const String _keyNeverPlayLanguages =
      '${AppConstants.settingsKeyPrefix}neverPlayLanguages';
  static const String _keyPlaybackSpeed =
      '${AppConstants.settingsKeyPrefix}playbackSpeed';

  late SharedPreferences _prefs;

  @override
  AppSettings build() {
    _prefs = ref.watch(sharedPrefsProvider);
    return AppSettings(
      themeMode: themeModeFromName(_prefs.getString(_keyThemeMode)) ??
          ThemeMode.system,
      accent: accentFromName(_prefs.getString(_keyAccent)) ??
          AccentColor.purple,
      reduceTransparency:
          _prefs.getBool(_keyReduceTransparency) ?? false,
      crossfadeSeconds: (_prefs.getDouble(_keyCrossfadeSeconds) ?? 0)
          .clamp(0, AppConstants.crossfadeMaxSeconds)
          .toDouble(),
      gaplessPlayback: _prefs.getBool(_keyGapless) ?? true,
      resumeOnStart: _prefs.getBool(_keyResumeOnStart) ?? true,
      storageTemplate:
          _prefs.getString(_keyStorageTemplate) ?? '{artist}/{album}/{title}',
      scanFolders: _readScanFolders(_prefs),
      neverPlayLanguages: _prefs.getStringList(_keyNeverPlayLanguages) ??
          const <String>[],
      playbackSpeed: (_prefs.getDouble(_keyPlaybackSpeed) ?? 1.0)
          .clamp(0.5, 2)
          .toDouble(),
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(_prefs.setString(_keyThemeMode, mode.name));
  }

  void setAccent(AccentColor accent) {
    state = state.copyWith(accent: accent);
    unawaited(_prefs.setString(_keyAccent, accent.name));
  }

  void setReduceTransparency(bool reduce) {
    state = state.copyWith(reduceTransparency: reduce);
    unawaited(_prefs.setBool(_keyReduceTransparency, reduce));
  }

  /// Clamps to `0..[AppConstants.crossfadeMaxSeconds]`.
  void setCrossfade(double seconds) {
    final clamped =
        seconds.clamp(0, AppConstants.crossfadeMaxSeconds).toDouble();
    state = state.copyWith(crossfadeSeconds: clamped);
    unawaited(_prefs.setDouble(_keyCrossfadeSeconds, clamped));
  }

  void setGapless(bool gapless) {
    state = state.copyWith(gaplessPlayback: gapless);
    unawaited(_prefs.setBool(_keyGapless, gapless));
  }

  void setResumeOnStart(bool resume) {
    state = state.copyWith(resumeOnStart: resume);
    unawaited(_prefs.setBool(_keyResumeOnStart, resume));
  }

  void setStorageTemplate(String template) {
    if (template.isEmpty) {
      return;
    }
    state = state.copyWith(storageTemplate: template);
    unawaited(_prefs.setString(_keyStorageTemplate, template));
  }

  /// Appends [folder] (no duplicates) and persists the list.
  void addScanFolder(String folder) {
    if (state.scanFolders.contains(folder)) {
      return;
    }
    final folders = <String>[...state.scanFolders, folder];
    state = state.copyWith(scanFolders: folders);
    _persistScanFolders(folders);
  }

  /// Removes [folder] when present and persists the list.
  void removeScanFolder(String folder) {
    if (!state.scanFolders.contains(folder)) {
      return;
    }
    final folders =
        state.scanFolders.where((f) => f != folder).toList(growable: false);
    state = state.copyWith(scanFolders: folders);
    _persistScanFolders(folders);
  }

  void setNeverPlayLanguages(List<String> languages) {
    final languagesCopy = List<String>.of(languages);
    state = state.copyWith(neverPlayLanguages: languagesCopy);
    unawaited(_prefs.setStringList(_keyNeverPlayLanguages, languagesCopy));
  }

  /// Clamps to `0.5..2.0` (matching the player speed menu).
  void setPlaybackSpeed(double speed) {
    final clamped = speed.clamp(0.5, 2).toDouble();
    state = state.copyWith(playbackSpeed: clamped);
    unawaited(_prefs.setDouble(_keyPlaybackSpeed, clamped));
  }

  /// Canonical storage format is a `StringList`. Falls back to the legacy
  /// JSON string written by the Folders tab flow (`ScanFoldersStore`, Task
  /// 3-b) so both writers stay readable until the settings screen is the
  /// only writer.
  List<String> _readScanFolders(SharedPreferences prefs) {
    final stored = prefs.getStringList(_keyScanFolders);
    if (stored != null) {
      return List<String>.of(stored);
    }
    final legacy = prefs.getString(_keyScanFolders);
    if (legacy == null) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(legacy);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on Object catch (_) {
      // Corrupt payload — fall through to the default.
    }
    return const <String>[];
  }

  void _persistScanFolders(List<String> folders) {
    unawaited(_prefs.setStringList(_keyScanFolders, folders));
  }
}

/// Owner-spec alias for [settingsNotifierProvider] so call sites read
/// `ref.watch(settingsProvider).themeMode`.
final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    settingsNotifierProvider;

/// Reduce-transparency flag consumed by [GlassCard] (design system).
///
/// Kept as a tiny manual provider so the design system does not have to
/// watch the whole [AppSettings] object; it re-points GlassCard from the
/// legacy `themeSettingsProvider` to the canonical settings (Task B, E1).
final Provider<bool> reduceTransparencyProvider = Provider<bool>(
  (ref) => ref.watch(settingsProvider).reduceTransparency,
);
