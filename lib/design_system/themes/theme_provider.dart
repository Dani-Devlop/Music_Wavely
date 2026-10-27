import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/design_system/tokens/colors.dart';

part 'theme_provider.freezed.dart';

/// User-facing theme preferences (mode + accent + accessibility switch).
@freezed
abstract class ThemeSettings with _$ThemeSettings {
  const factory ThemeSettings({
    @Default(ThemeMode.system) ThemeMode mode,
    @Default(WavelyAccent.purple) WavelyAccent accent,
    @Default(false) bool reduceTransparency,
  }) = _ThemeSettings;
}

/// Loads, keeps and persists [ThemeSettings].
class ThemeSettingsNotifier extends StateNotifier<ThemeSettings> {
  ThemeSettingsNotifier({SettingsStore? store}) : super(const ThemeSettings()) {
    unawaited(_load(store));
  }

  static const String _keyThemeMode =
      '${AppConstants.settingsKeyPrefix}themeMode';
  static const String _keyAccent = '${AppConstants.settingsKeyPrefix}accent';
  static const String _keyReduceTransparency =
      '${AppConstants.settingsKeyPrefix}reduceTransparency';

  SettingsStore? _store;

  void setMode(ThemeMode mode) {
    state = state.copyWith(mode: mode);
    unawaited(_persist(_keyThemeMode, _themeModeToString(mode)));
  }

  void setAccent(WavelyAccent accent) {
    state = state.copyWith(accent: accent);
    unawaited(_persist(_keyAccent, _accentToString(accent)));
  }

  void setReduceTransparency(bool reduce) {
    state = state.copyWith(reduceTransparency: reduce);
    unawaited(_persist(_keyReduceTransparency, reduce));
  }

  Future<void> _load(SettingsStore? store) async {
    if (store == null) {
      return;
    }
    _store = store;
    try {
      final modeRaw = await store.read<String>(_keyThemeMode);
      final accentRaw = await store.read<String>(_keyAccent);
      final reduceRaw = await store.read<bool>(_keyReduceTransparency);
      state = state.copyWith(
        mode: _themeModeFromString(modeRaw) ?? state.mode,
        accent: _accentFromString(accentRaw) ?? state.accent,
        reduceTransparency: reduceRaw ?? state.reduceTransparency,
      );
    } on Object catch (_) {
      // Corrupt or unreadable settings are ignored; defaults stay in place.
    }
  }

  Future<void> _persist(String key, Object? value) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.write(key, value);
  }

  static ThemeMode? _themeModeFromString(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };

  static String _themeModeToString(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static WavelyAccent? _accentFromString(String? raw) => switch (raw) {
        'purple' => WavelyAccent.purple,
        'green' => WavelyAccent.green,
        _ => null,
      };

  static String _accentToString(WavelyAccent accent) => switch (accent) {
        WavelyAccent.purple => 'purple',
        WavelyAccent.green => 'green',
      };
}

/// Default settings storage binding (swap for a SharedPreferences-backed
/// store in the app bootstrap).
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => InMemorySettingsStore(),
);

/// Reactive theme settings consumed by the app shell.
final themeSettingsProvider =
    StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
  (ref) => ThemeSettingsNotifier(store: ref.watch(settingsStoreProvider)),
);
