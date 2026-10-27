// authored, awaiting local run.
//
// SharedPreferencesSettingsStore tests
// (`lib/data/repositories/shared_prefs_settings_store.dart`) using
// `SharedPreferences.setMockInitialValues` (no plugin channels). Covers a
// read/write roundtrip for every supported value type (String, int, bool,
// double, List<String>), the documented `write(null)` -> remove-key
// semantics, the ignore-rule for unsupported value types, type-mismatch
// reads resolving to null, missing-key reads and use through the abstract
// SettingsStore interface.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/repositories/shared_prefs_settings_store.dart';

void main() {
  const prefix = AppConstants.settingsKeyPrefix;

  late SharedPreferences prefs;
  late SharedPreferencesSettingsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    store = SharedPreferencesSettingsStore(prefs);
  });

  group('roundtrip per supported key type', () {
    test('String values roundtrip', () async {
      const key = '${prefix}theme.mode';
      await store.write(key, 'dark');
      expect(await store.read<String>(key), 'dark');
      expect(prefs.getString(key), 'dark');
    });

    test('int values roundtrip', () async {
      const key = AppConstants.queueIndexPersistKey;
      await store.write(key, 3);
      expect(await store.read<int>(key), 3);
      expect(prefs.getInt(key), 3);
    });

    test('bool values roundtrip', () async {
      const key = '${prefix}shuffle.enabled';
      await store.write(key, true);
      expect(await store.read<bool>(key), isTrue);
      await store.write(key, false);
      expect(await store.read<bool>(key), isFalse);
    });

    test('double values roundtrip', () async {
      const key = '${prefix}playback.speed';
      await store.write(key, 1.5);
      expect(await store.read<double>(key), 1.5);
      expect(prefs.getDouble(key), 1.5);
    });

    test('List<String> values roundtrip', () async {
      const key = '${prefix}folders.pinned';
      const value = <String>['/music/a', '/music/b'];
      await store.write(key, value);
      expect(await store.read<List<String>>(key), value);
      expect(prefs.getStringList(key), value);
    });

    test('empty string and zero are preserved (not treated as missing)',
        () async {
      await store.write('${prefix}a', '');
      await store.write('${prefix}b', 0);
      expect(await store.read<String>('${prefix}a'), '');
      expect(await store.read<int>('${prefix}b'), 0);
    });
  });

  group('write(null) removes', () {
    test('an existing key is removed by writing null', () async {
      const key = '${prefix}playback.speed';
      await store.write(key, 1.25);
      expect(await store.read<double>(key), 1.25);

      await store.write(key, null);
      expect(await store.read<double>(key), isNull);
      expect(prefs.containsKey(key), isFalse);
    });

    test('writing null on a missing key is a harmless no-op', () async {
      await store.write('${prefix}never.was', null);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('unsupported value types', () {
    test('are ignored without throwing', () async {
      const key = '${prefix}unsupported';
      await store.write(key, <String, int>{'a': 1});
      expect(await store.read<String>(key), isNull);
      expect(prefs.get(key), isNull);
    });

    test('leave a previously stored value untouched', () async {
      const key = '${prefix}theme.mode';
      await store.write(key, 'dark');
      await store.write(key, DateTime(2024));
      expect(await store.read<String>(key), 'dark');
    });
  });

  group('read type dispatch', () {
    test('a missing key resolves to null for every T', () async {
      const key = '${prefix}missing';
      expect(await store.read<String>(key), isNull);
      expect(await store.read<int>(key), isNull);
      expect(await store.read<bool>(key), isNull);
      expect(await store.read<double>(key), isNull);
      expect(await store.read<List<String>>(key), isNull);
    });

    test('a type mismatch resolves to null (string stored, int read)',
        () async {
      const key = '${prefix}theme.mode';
      await store.write(key, 'dark');
      expect(await store.read<int>(key), isNull);
      expect(await store.read<bool>(key), isNull);
      expect(await store.read<String>(key), 'dark');
    });

    test('reading double for an int-stored value resolves to null',
        () async {
      const key = AppConstants.queueIndexPersistKey;
      await store.write(key, 2);
      expect(await store.read<double>(key), isNull);
      expect(await store.read<int>(key), 2);
    });

    test('an unsupported T resolves to null', () async {
      const key = '${prefix}theme.mode';
      await store.write(key, 'dark');
      expect(await store.read<DateTime>(key), isNull);
    });
  });

  group('SettingsStore interface', () {
    test('works through the abstract store type', () async {
      final SettingsStore abstracted = store;
      const key = AppConstants.queuePersistKey;
      await abstracted.write(key, '10,11,12');
      expect(await abstracted.read<String>(key), '10,11,12');
      await abstracted.write(key, null);
      expect(await abstracted.read<String>(key), isNull);
    });

    test('values survive across store instances over the same prefs',
        () async {
      const key = '${prefix}sleep.preset';
      await store.write(key, 30);
      final reopened = SharedPreferencesSettingsStore(prefs);
      expect(await reopened.read<int>(key), 30);
    });
  });
}
