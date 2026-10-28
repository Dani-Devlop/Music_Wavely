// authored, awaiting local run.
//
// Tests for lib/features/settings/data/update_service.dart: version
// compare, platform asset picking, up-to-date / update-available paths,
// failure degradation and the installer seam.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:wavely/features/settings/data/update_service.dart';

http.Response _release(Object? assets, {String tag = 'v1.3.0'}) =>
    http.Response(
      jsonEncode(<String, Object?>{
        'tag_name': tag,
        'html_url': 'https://github.com/Dani-Devlop/Music_Wavely/releases/tag/$tag',
        'assets': assets,
      }),
      200,
    );

class _ScriptedClient extends http_testing.MockClient {
  _ScriptedClient(Future<http.Response> Function(http.Request) fn)
      : super((request) => fn(request));

  static _ScriptedClient single(http.Response response) =>
      _ScriptedClient((_) async => response);

  static _ScriptedClient failing() =>
      _ScriptedClient((_) async => throw StateError('offline'));
}

class _RecordingInstaller implements UpdateInstaller {
  final List<String> installed = <String>[];

  @override
  Future<void> install(String url) async => installed.add(url);
}

void main() {
  group('compareVersions', () {
    test('numeric-aware ordering', () {
      expect(compareVersions('1.2.9', '1.2.10'), isNegative);
      expect(compareVersions('v1.2.10', '1.2.9'), isPositive);
      expect(compareVersions('1.0.0', 'v1.0.0'), 0);
      expect(compareVersions('0.1.0', '0.1.1'), isNegative);
      expect(compareVersions('2.0', '1.9.9'), isPositive);
    });

    test('ignores build metadata', () {
      expect(compareVersions('1.2.3+1', 'v1.2.3'), 0);
    });
  });

  group('checkForUpdate', () {
    test('up-to-date when current >= latest', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[], tag: 'v0.1.0')),
        currentVersion: '0.1.0',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isFalse);
    });

    test('update available with matching platform asset', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          <String, Object?>{
            'name': 'wavely-v1.3.0-android-arm64.apk',
            'browser_download_url':
                'https://github.com/x/wavely-v1.3.0-android-arm64.apk',
          },
          <String, Object?>{
            'name': 'Wavely-v1.3.0-windows-x64.msix',
            'browser_download_url':
                'https://github.com/x/Wavely-v1.3.0-windows-x64.msix',
          },
        ])),
        currentVersion: '0.1.0',
        // Test seam: pretend we run on Windows.
        assetSuffixFor: () => '.msix',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isTrue);
      expect(result.latestVersion, 'v1.3.0');
      expect(result.assetName, 'wavely-v1.3.0-windows-x64.msix'.toLowerCase());
      expect(result.assetUrl, 'https://github.com/x/Wavely-v1.3.0-windows-x64.msix');
      expect(
        result.releaseUrl,
        contains('releases/tag/v1.3.0'),
      );
    });

    test('no matching asset → available with releaseUrl fallback only',
        () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          <String, Object?>{
            'name': 'source.tar.gz',
            'browser_download_url': 'https://github.com/x/source.tar.gz',
          },
        ])),
        currentVersion: '0.1.0',
        assetSuffixFor: () => '.msix',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isTrue);
      expect(result.assetUrl, isNull);
      expect(result.releaseUrl, isNotNull);
    });

    test('non-200 degrades to up-to-date (never throws)', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(http.Response('rate limited', 403)),
        currentVersion: '0.1.0',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isFalse);
    });

    test('network failure degrades to up-to-date (never throws)', () async {
      final service = UpdateService(
        client: _ScriptedClient.failing(),
        currentVersion: '0.1.0',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isFalse);
    });
  });

  group('downloadAndInstall', () {
    test('routes the asset URL through the injected installer', () async {
      final installer = _RecordingInstaller();
      final service = UpdateService(
        currentVersion: '0.1.0',
        installer: installer,
      );
      final bool ok = await service.downloadAndInstall(
        UpdateCheckResult.available(
          currentVersion: '0.1.0',
          latestVersion: 'v1.3.0',
          releaseUrl: 'https://github.com/Dani-Devlop/Music_Wavely/releases',
          assetUrl: 'https://github.com/x/wavely.msix',
          assetName: 'wavely.msix',
        ),
      );
      expect(ok, isTrue);
      expect(installer.installed.single, 'https://github.com/x/wavely.msix');
    });

    test('without an installer the call reports false honestly', () async {
      final service = UpdateService(currentVersion: '0.1.0');
      final bool ok = await service.downloadAndInstall(
        UpdateCheckResult.available(
          currentVersion: '0.1.0',
          latestVersion: 'v1.3.0',
          releaseUrl: 'https://github.com/Dani-Devlop/Music_Wavely/releases',
        ),
      );
      expect(ok, isFalse);
    });
  });
}
