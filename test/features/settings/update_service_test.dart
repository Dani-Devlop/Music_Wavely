// Tests for lib/features/settings/data/update_service.dart (Stage 7):
// pub_semver version compare, platform asset picking (Android ABI split
// preference, Windows MSIX preference), up-to-date / update-available
// paths, failure degradation and the installer seam outcomes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:wavely/features/settings/data/update_service.dart';

http.Response _release(
  Object? assets, {
  String tag = 'v1.3.0',
  String body = '',
}) =>
    http.Response(
      jsonEncode(<String, Object?>{
        'tag_name': tag,
        'html_url': 'https://github.com/Dani-Devlop/Music_Wavely/releases/tag/$tag',
        'body': body,
        'published_at': '2026-11-04T00:00:00Z',
        'assets': assets,
      }),
      200,
    );

_MapAsset _asset(String name, {int size = 12345}) => _MapAsset(
      name: name,
      url: 'https://github.com/x/$name',
      size: size,
    );

class _MapAsset {
  const _MapAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'browser_download_url': url,
        'size': size,
      };
}

class _ScriptedClient extends http_testing.MockClient {
  _ScriptedClient(Future<http.Response> Function(http.Request) fn)
      : super((request) => fn(request));

  static _ScriptedClient single(http.Response response) =>
      _ScriptedClient((_) async => response);

  static _ScriptedClient failing() =>
      _ScriptedClient((_) async => throw StateError('offline'));
}

class _RecordingInstaller implements UpdateInstaller {
  final List<UpdateCheckResult> installed = <UpdateCheckResult>[];

  @override
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    installed.add(result);
    return const UpdaterUiLaunched();
  }
}

void main() {
  group('compareVersions (pub_semver backed)', () {
    test('numeric-aware ordering', () {
      expect(compareVersions('1.2.9', '1.2.10'), isNegative);
      expect(compareVersions('v1.2.10', '1.2.9'), isPositive);
      expect(compareVersions('1.0.0', 'v1.0.0'), 0);
      expect(compareVersions('0.1.0', '0.1.1'), isNegative);
      expect(compareVersions('2.0', '1.9.9'), isPositive);
      expect(compareVersions('1.10.0', '1.9.0'), isPositive);
    });

    test('ignores build metadata (tag vs PackageInfo form)', () {
      expect(compareVersions('1.2.3+1', 'v1.2.3'), 0);
      expect(compareVersions('1.0.1+5', 'v1.0.1'), 0);
      expect(compareVersions('1.0.1+5', 'v1.0.2'), isNegative);
    });

    test('unparseable inputs degrade to a string compare', () {
      expect(compareVersions('beta', 'alpha'), isPositive);
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
          _asset('wavely-v1.3.0-android-arm64-v8a.apk').toMap(),
          _asset('Wavely-v1.3.0-windows-x64.msix').toMap(),
        ])),
        currentVersion: '0.1.0',
        // Test seam: pretend we run on Windows.
        assetSuffixFor: () => '.msix',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.updateAvailable, isTrue);
      expect(result.latestVersion, 'v1.3.0');
      expect(result.assetName, 'wavely-v1.3.0-windows-x64.msix');
      expect(result.assetUrl, 'https://github.com/x/Wavely-v1.3.0-windows-x64.msix');
      expect(
        result.releaseUrl,
        contains('releases/tag/v1.3.0'),
      );
    });

    test('surfaces release notes, publish date and asset size', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(
          _release(<Object?>[_asset('wavely.msix').toMap()],
              body: 'Auto-update system'),
        ),
        currentVersion: '0.1.0',
        assetSuffixFor: () => '.msix',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.releaseNotes, 'Auto-update system');
      expect(result.publishedAt, DateTime.utc(2026, 11, 4));
      expect(result.assetSizeBytes, 12345);
    });

    test('Android prefers the device-ABI APK split', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          _asset('wavely-v1.3.0-android-universal.apk').toMap(),
          _asset('wavely-v1.3.0-android-arm64-v8a.apk').toMap(),
          _asset('wavely-v1.3.0-android-armeabi-v7a.apk').toMap(),
        ])),
        currentVersion: '0.1.0',
        assetSuffixFor: () => '.apk',
        androidAbi: 'arm64-v8a',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.assetName, contains('arm64-v8a'));
    });

    test('Android falls back to the universal APK', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          _asset('wavely-v1.3.0-android-universal.apk').toMap(),
        ])),
        currentVersion: '0.1.0',
        assetSuffixFor: () => '.apk',
        androidAbi: 'x86_64',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.assetName, contains('universal'));
    });

    test('Windows prefers the MSIX over the ZIP bundle', () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          _asset('wavely-v1.3.0-windows-x64.zip').toMap(),
          _asset('wavely.msix').toMap(),
        ])),
        currentVersion: '0.1.0',
        assetSuffixFor: () => '.msix',
      );
      final UpdateCheckResult result = await service.checkForUpdate();
      expect(result.assetName, 'wavely.msix');
    });

    test('no matching asset → available with releaseUrl fallback only',
        () async {
      final service = UpdateService(
        client: _ScriptedClient.single(_release(<Object?>[
          _asset('source.tar.gz').toMap(),
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

  group('install', () {
    test('routes the release through the injected installer', () async {
      final installer = _RecordingInstaller();
      final service = UpdateService(
        currentVersion: '0.1.0',
        installer: installer,
      );
      final UpdateInstallOutcome outcome = await service.install(
        UpdateCheckResult.available(
          currentVersion: '0.1.0',
          latestVersion: 'v1.3.0',
          releaseUrl: 'https://github.com/Dani-Devlop/Music_Wavely/releases',
          assetUrl: 'https://github.com/x/wavely.msix',
          assetName: 'wavely.msix',
        ),
      );
      expect(outcome, isA<UpdaterUiLaunched>());
      expect(installer.installed.single.assetName, 'wavely.msix');
    });

    test('without an installer the call reports failure honestly', () async {
      final service = UpdateService(currentVersion: '0.1.0');
      final UpdateInstallOutcome outcome = await service.install(
        UpdateCheckResult.available(
          currentVersion: '0.1.0',
          latestVersion: 'v1.3.0',
          releaseUrl: 'https://github.com/Dani-Devlop/Music_Wavely/releases',
        ),
      );
      expect(outcome, isA<InstallFailed>());
    });

    test('a non-update result is rejected', () async {
      final installer = _RecordingInstaller();
      final service = UpdateService(
        currentVersion: '0.1.0',
        installer: installer,
      );
      final UpdateInstallOutcome outcome = await service.install(
        UpdateCheckResult.upToDate('0.1.0'),
      );
      expect(outcome, isA<InstallFailed>());
      expect(installer.installed, isEmpty);
    });

    test('installer exceptions degrade to InstallFailed (never throw)',
        () async {
      final service = UpdateService(
        currentVersion: '0.1.0',
        installer: _ThrowingInstaller(),
      );
      final UpdateInstallOutcome outcome = await service.install(
        UpdateCheckResult.available(
          currentVersion: '0.1.0',
          latestVersion: 'v1.3.0',
          releaseUrl: 'https://github.com/Dani-Devlop/Music_Wavely/releases',
        ),
      );
      expect(outcome, isA<InstallFailed>());
    });
  });
}

class _ThrowingInstaller implements UpdateInstaller {
  @override
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    throw StateError('boom');
  }
}
