// authored, awaiting local run.
//
// Tests for lib/sources/source_registry.dart: SourceSettings persistence
// (mock SharedPreferences + in-memory credential store), enable flags,
// and SourceRegistry construction (resolveEnabled / describeAll /
// buildById).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/sources/source_registry.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';

void main() {
  group('SourceSettings', () {
    late SourceSettings settings;
    late InMemorySubsonicCredentialStore credentials;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      credentials = InMemorySubsonicCredentialStore();
      settings = SourceSettings(prefs, credentials: credentials);
    });

    test('subsonic is null when not configured', () async {
      expect(await settings.loadSubsonic(), isNull);
    });

    test('saveSubsonic merges public JSON + secure password', () async {
      await settings.saveSubsonic(
        const SubsonicConfig(
          url: 'https://music.example.com',
          username: 'dani',
          password: 'pw',
        ),
      );
      expect(await credentials.read(), 'pw');
      final SubsonicConfig? loaded = await settings.loadSubsonic();
      expect(loaded, isNotNull);
      expect(loaded!.url, 'https://music.example.com');
      expect(loaded.password, 'pw');
    });

    test('empty password delete removes the stored secret', () async {
      await settings.saveSubsonic(
        const SubsonicConfig(
          url: 'https://x',
          username: 'u',
          password: 'old',
        ),
      );
      await settings.saveSubsonic(
        const SubsonicConfig(url: 'https://x', username: 'u', password: ''),
      );
      expect(await credentials.read(), isNull);
      // Still configured (url+username survive without a password).
      expect(await settings.loadSubsonic(), isNotNull);
    });

    test('clearSubsonic removes config + secret', () async {
      await settings.saveSubsonic(
        const SubsonicConfig(
          url: 'https://x',
          username: 'u',
          password: 'pw',
        ),
      );
      await settings.clearSubsonic();
      expect(await settings.loadSubsonic(), isNull);
      expect(await credentials.read(), isNull);
    });

    test('jamendo client id persists and clears with null/empty', () async {
      expect(settings.loadJamendoClientId(), isNull);
      await settings.saveJamendoClientId(' my-id ');
      expect(settings.loadJamendoClientId(), 'my-id');
      await settings.saveJamendoClientId(null);
      expect(settings.loadJamendoClientId(), isNull);
      await settings.saveJamendoClientId('  ');
      expect(settings.loadJamendoClientId(), isNull);
    });

    test('enable flags default to true and persist', () async {
      expect(settings.isSourceEnabled('subsonic'), isTrue);
      await settings.setSourceEnabled('subsonic', false);
      expect(settings.isSourceEnabled('subsonic'), isFalse);
      expect(settings.isSourceEnabled('jamendo'), isTrue);
    });
  });

  group('SourceRegistry', () {
    late SourceSettings settings;
    late SourceRegistry registry;
    late InMemorySubsonicCredentialStore credentials;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      credentials = InMemorySubsonicCredentialStore();
      settings = SourceSettings(prefs, credentials: credentials);
      registry = SourceRegistry(settings);
    });

    test('describeAll lists the four sources with configured=false for '
        'unconfigured ones', () async {
      final List<SourceDescriptor> all = await registry.describeAll();
      expect(all.map((SourceDescriptor d) => d.id), <String>[
        'subsonic',
        'jamendo',
        'archive',
        'fma',
      ]);
      expect(all.first.configured, isFalse);
      expect(all[2].configured, isTrue); // archive.org needs nothing
      expect(all[3].configured, isTrue); // FMA needs nothing
    });

    test('resolveEnabled only returns configured + enabled sources',
        () async {
      expect((await registry.resolveEnabled()).map((s) => s.id),
          <String>['archive', 'fma']);
      await settings.saveJamendoClientId('id');
      expect((await registry.resolveEnabled()).map((s) => s.id),
          <String>['jamendo', 'archive', 'fma']);
      await settings.setSourceEnabled('jamendo', false);
      expect((await registry.resolveEnabled()).map((s) => s.id),
          <String>['archive', 'fma']);
    });

    test('buildById finds enabled sources and misses disabled ones',
        () async {
      expect((await registry.buildById('archive'))!.id, 'archive');
      expect(await registry.buildById('subsonic'), isNull);
    });
  });
}
