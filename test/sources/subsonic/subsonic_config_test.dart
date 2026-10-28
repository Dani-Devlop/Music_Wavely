// authored, awaiting local run.
//
// Unit tests for lib/sources/subsonic/subsonic_config.dart: public-JSON
// round trip, base-URL normalisation, credential store behaviour
// (in-memory), and the isComplete gate.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';

void main() {
  group('SubsonicConfig', () {
    test('defaults the API version to 1.16.1', () {
      const SubsonicConfig c = SubsonicConfig(
        url: 'https://music.example.com',
        username: 'u',
        password: 'p',
      );
      expect(c.apiVersion, '1.16.1');
      expect(c.enabled, isTrue);
    });

    test('baseUrl trims trailing slashes and whitespace', () {
      const SubsonicConfig c = SubsonicConfig(
        url: '  https://music.example.com/  ',
        username: 'u',
        password: 'p',
      );
      expect(c.baseUrl, 'https://music.example.com');
    });

    test('isComplete requires url + username', () {
      expect(
        const SubsonicConfig(url: '', username: '', password: '').isComplete,
        isFalse,
      );
      expect(
        const SubsonicConfig(url: 'https://x', username: '', password: '')
            .isComplete,
        isFalse,
      );
      expect(
        const SubsonicConfig(url: 'https://x', username: 'u', password: '')
            .isComplete,
        isTrue,
      );
    });

    test('public JSON round trip keeps non-secret fields only', () {
      const SubsonicConfig c = SubsonicConfig(
        url: 'https://music.example.com',
        username: 'u',
        password: 'secret',
        enabled: false,
      );
      final Map<String, dynamic> json = c.toPublicJson();
      expect(json.containsKey('password'), isFalse);
      final SubsonicConfig restored = SubsonicConfig.fromPublicJson(
        json,
        password: 'from-store',
      );
      expect(restored.url, c.url);
      expect(restored.username, c.username);
      expect(restored.apiVersion, c.apiVersion);
      expect(restored.enabled, isFalse);
      expect(restored.password, 'from-store');
    });

    test('copyWith replaces only the given fields', () {
      const SubsonicConfig c = SubsonicConfig(
        url: 'https://a',
        username: 'u',
        password: 'p',
      );
      final SubsonicConfig c2 = c.copyWith(enabled: false);
      expect(c2.enabled, isFalse);
      expect(c2.url, 'https://a');
      expect(c2.password, 'p');
    });
  });

  group('InMemorySubsonicCredentialStore', () {
    test('write / read / delete round trip', () async {
      final InMemorySubsonicCredentialStore store =
          InMemorySubsonicCredentialStore();
      expect(await store.read(), isNull);
      await store.write('s3cret');
      expect(await store.read(), 's3cret');
      await store.delete();
      expect(await store.read(), isNull);
    });
  });
}
