/// authored, awaiting local run.
///
/// Exercises the real `SettingsNotifier` graph: persistence roundtrip
/// through `SharedPreferences.setMockInitialValues` +
/// `sharedPrefsProvider.overrideWithValue`, the tolerant-read fallbacks
/// (unknown enum names, missing keys, corrupt legacy JSON) and the setter
/// clamping documented in lib/features/settings/data/settings_provider.dart.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/domain/settings.dart';

String _key(String suffix) => '${AppConstants.settingsKeyPrefix}$suffix';

ProviderContainer _container(SharedPreferences prefs) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
  );
  return container;
}

Future<void> _flushWrites() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaults (absent keys)', () {
    test('fresh store yields documented AppSettings defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      final AppSettings settings = container.read(settingsProvider);

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.accent, AccentColor.purple);
      expect(settings.reduceTransparency, isFalse);
      expect(settings.crossfadeSeconds, 0);
      expect(settings.gaplessPlayback, isTrue);
      expect(settings.resumeOnStart, isTrue);
      expect(settings.storageTemplate, '{artist}/{album}/{title}');
      expect(settings.scanFolders, isEmpty);
      expect(settings.neverPlayLanguages, isEmpty);
      expect(settings.playbackSpeed, 1.0);
    });
  });

  group('tolerant reads', () {
    test('unknown theme-mode / accent names fall back to defaults',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key('themeMode'): 'baroque',
        _key('accent'): 'magenta',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      final AppSettings settings = container.read(settingsProvider);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.accent, AccentColor.purple);
    });

    test('out-of-range persisted numbers are clamped on load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key('crossfadeSeconds'): 999.0,
        _key('playbackSpeed'): -3.0,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      final AppSettings settings = container.read(settingsProvider);
      expect(settings.crossfadeSeconds, AppConstants.crossfadeMaxSeconds);
      expect(settings.playbackSpeed, 0.5);
    });

    test('corrupt legacy scanFolders JSON degrades to an empty list',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key('scanFolders'): '{not json at all',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(settingsProvider).scanFolders, isEmpty);
    });

    test('legacy JSON-string scanFolders is parsed (Folders-tab format)',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _key('scanFolders'): '["/legacy/a","/legacy/b"]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      expect(
        container.read(settingsProvider).scanFolders,
        <String>['/legacy/a', '/legacy/b'],
      );
    });

    test('tolerant parsers behave per contract (unit level)', () {
      expect(themeModeFromName('dark'), ThemeMode.dark);
      expect(themeModeFromName('LIGHT'), isNull,
          reason: 'names are matched exactly, not case-folded');
      expect(themeModeFromName(null), isNull);
      expect(accentFromName('green'), AccentColor.green);
      expect(accentFromName('chartreuse'), isNull);
    });
  });

  group('persistence roundtrip', () {
    test('setters update state AND write through to SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);
      final SettingsNotifier notifier =
          container.read(settingsProvider.notifier);

      notifier
        ..setThemeMode(ThemeMode.dark)
        ..setAccent(AccentColor.green)
        ..setReduceTransparency(true)
        ..setCrossfade(4.5)
        ..setGapless(false)
        ..setNeverPlayLanguages(<String>['de', 'fr'])
        ..setPlaybackSpeed(1.5)
        ..setStorageTemplate('{artist}/{title}')
        ..addScanFolder('/music/a')
        ..addScanFolder('/music/b');
      await _flushWrites();

      final AppSettings state = container.read(settingsProvider);
      expect(state.themeMode, ThemeMode.dark);
      expect(state.accent, AccentColor.green);
      expect(state.reduceTransparency, isTrue);
      expect(state.crossfadeSeconds, 4.5);
      expect(state.gaplessPlayback, isFalse);
      expect(state.neverPlayLanguages, <String>['de', 'fr']);
      expect(state.playbackSpeed, 1.5);
      expect(state.storageTemplate, '{artist}/{title}');
      expect(state.scanFolders, <String>['/music/a', '/music/b']);

      expect(prefs.getString(_key('themeMode')), 'dark');
      expect(prefs.getString(_key('accent')), 'green');
      expect(prefs.getBool(_key('reduceTransparency')), isTrue);
      expect(prefs.getDouble(_key('crossfadeSeconds')), 4.5);
      expect(prefs.getBool(_key('gapless')), isFalse);
      expect(prefs.getStringList(_key('neverPlayLanguages')),
          <String>['de', 'fr']);
      expect(prefs.getDouble(_key('playbackSpeed')), 1.5);
      expect(prefs.getString(_key('storageTemplate')), '{artist}/{title}');
      expect(prefs.getStringList(_key('scanFolders')),
          <String>['/music/a', '/music/b']);
    });

    test('a fresh notifier over the same store reloads persisted values',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer first = _container(prefs);
      first.read(settingsProvider.notifier)
        ..setThemeMode(ThemeMode.light)
        ..setCrossfade(7)
        ..setPlaybackSpeed(0.75)
        ..setResumeOnStart(false)
        ..addScanFolder('/music/kept')
        ..setNeverPlayLanguages(<String>['ja']);
      await _flushWrites();
      await first.dispose();

      final ProviderContainer second = _container(prefs);
      addTearDown(second.dispose);
      final AppSettings reloaded = second.read(settingsProvider);

      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.crossfadeSeconds, 7);
      expect(reloaded.playbackSpeed, 0.75);
      expect(reloaded.resumeOnStart, isFalse);
      expect(reloaded.scanFolders, <String>['/music/kept']);
      expect(reloaded.neverPlayLanguages, <String>['ja']);
    });

    test('reduceTransparencyProvider re-points to the canonical setting',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);

      expect(container.read(reduceTransparencyProvider), isFalse);
      container.read(settingsProvider.notifier).setReduceTransparency(true);
      expect(container.read(reduceTransparencyProvider), isTrue);
    });
  });

  group('setter guards', () {
    test('crossfade clamps to the 0..12s token, speed to 0.5..2.0',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);
      final SettingsNotifier notifier =
          container.read(settingsProvider.notifier);

      notifier.setCrossfade(99);
      expect(container.read(settingsProvider).crossfadeSeconds,
          AppConstants.crossfadeMaxSeconds.toDouble());
      expect(prefs.getDouble(_key('crossfadeSeconds')), 12.0);

      notifier.setPlaybackSpeed(5);
      expect(container.read(settingsProvider).playbackSpeed, 2.0);
      notifier.setPlaybackSpeed(0.1);
      expect(container.read(settingsProvider).playbackSpeed, 0.5);
      expect(prefs.getDouble(_key('playbackSpeed')), 0.5);
    });

    test('duplicate scan folders and empty templates are no-ops', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);
      final SettingsNotifier notifier =
          container.read(settingsProvider.notifier);

      notifier
        ..addScanFolder('/music/a')
        ..addScanFolder('/music/a')
        ..setStorageTemplate('');
      await _flushWrites();

      expect(container.read(settingsProvider).scanFolders, <String>[
        '/music/a',
      ]);
      expect(container.read(settingsProvider).storageTemplate,
          '{artist}/{album}/{title}');
    });

    test('removeScanFolder drops only the requested folder', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = _container(prefs);
      addTearDown(container.dispose);
      final SettingsNotifier notifier =
          container.read(settingsProvider.notifier);

      notifier
        ..addScanFolder('/music/a')
        ..addScanFolder('/music/b')
        ..removeScanFolder('/music/a')
        ..removeScanFolder('/music/gone');
      await _flushWrites();

      expect(container.read(settingsProvider).scanFolders, <String>[
        '/music/b',
      ]);
      expect(prefs.getStringList(_key('scanFolders')), <String>['/music/b']);
    });
  });
}
