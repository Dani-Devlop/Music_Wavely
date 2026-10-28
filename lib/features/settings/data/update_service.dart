import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:wavely/features/settings/data/update_platform.dart';

/// Result of an update check against GitHub Releases.
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.updateAvailable,
    required this.currentVersion,
    this.latestVersion,
    this.releaseUrl,
    this.assetUrl,
    this.assetName,
  });

  /// Up-to-date marker.
  factory UpdateCheckResult.upToDate(String currentVersion) =>
      UpdateCheckResult._(updateAvailable: false, currentVersion: currentVersion);

  /// An installable release is available.
  factory UpdateCheckResult.available({
    required String currentVersion,
    required String latestVersion,
    required String releaseUrl,
    String? assetUrl,
    String? assetName,
  }) =>
      UpdateCheckResult._(
        updateAvailable: true,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseUrl: releaseUrl,
        assetUrl: assetUrl,
        assetName: assetName,
      );

  final bool updateAvailable;
  final String currentVersion;
  final String? latestVersion;
  final String? releaseUrl;

  /// Direct download URL of the asset matching the running platform.
  final String? assetUrl;
  final String? assetName;
}

/// Download/install strategy seam. Tests inject a recorder; the default
/// implementation opens the release page / asset in the external browser
/// (keeping the install flow user-visible instead of silently replacing
/// the binary — the Sparkle/WinSparkle path via `auto_updater` is documented
/// in docs/PACKAGING.md and left for the packaging milestone).
abstract interface class UpdateInstaller {
  /// Installs (or surfaces) the given release/asset URL.
  Future<void> install(String url);
}

/// Auto-update service over the GitHub Releases API (Stage 2.2).
///
/// - `checkForUpdate()` resolves the latest release for
///   `Dani-Devlop/Music_Wavely` and picks the asset matching the running
///   platform (`.msix`/`.exe` on Windows, `.AppImage` on Linux,
///   `.apk` on Android; macOS `.dmg`).
/// - Version comparison is a tolerant semver-ish numeric-aware compare
///   (`v1.2.10 > v1.2.9`, prefixes `v` ignored).
/// - Never throws: failures surface as a "check failed" result.
class UpdateService {
  /// Creates the service.
  ///
  /// [currentVersion] defaults to the compile-time `APP_VERSION` define
  /// (wired in tests); [releasesApi] targets the owner's repo;
  /// [assetSuffixFor] overrides the platform-asset picker in tests.
  UpdateService({
    http.Client? client,
    String? currentVersion,
    Uri? releasesApi,
    UpdateInstaller? installer,
    String Function()? assetSuffixFor,
  })  : _client = client ?? http.Client(),
        _currentVersion = currentVersion ?? const String.fromEnvironment('APP_VERSION'),
        _releasesApi = releasesApi ?? Uri.https(
          'api.github.com',
          '/repos/Dani-Devlop/Music_Wavely/releases/latest',
        ),
        _installer = installer,
        assetSuffixFor = assetSuffixFor;

  /// Releases page shown when no platform asset matches.
  static const String releasesPage =
      'https://github.com/Dani-Devlop/Music_Wavely/releases';

  final http.Client _client;
  final String _currentVersion;
  final Uri _releasesApi;
  final UpdateInstaller? _installer;

  /// Test seam over the platform-asset suffix picker.
  final String Function()? assetSuffixFor;

  /// Checks GitHub for a newer release. Never throws.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final http.Response response = await _client.get(
        _releasesApi,
        headers: const <String, String>{
          'accept': 'application/vnd.github+json',
        },
      );
      if (response.statusCode != 200) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final String tagName = (decoded['tag_name'] ?? '').toString();
      final String htmlUrl = (decoded['html_url'] ?? releasesPage).toString();
      final String latest = tagName.isNotEmpty ? tagName : releasesPage;
      if (latest.isEmpty ||
          compareVersions(_currentVersion, latest) >= 0) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final List<Object?> assets =
          decoded['assets'] is List ? decoded['assets'] as List<Object?> : const <Object?>[];
      final _AssetMatch match = _pickAsset(assets);
      return UpdateCheckResult.available(
        currentVersion: _currentVersion,
        latestVersion: latest,
        releaseUrl: htmlUrl,
        assetUrl: match.url,
        assetName: match.name,
      );
    } on Object {
      return UpdateCheckResult.upToDate(_currentVersion);
    }
  }

  /// Installs (or surfaces) the given asset/release URL through the
  /// injected installer; without one it falls back to `false` (the caller
  /// shows the release page instead).
  Future<bool> downloadAndInstall(UpdateCheckResult result) async {
    final String? url = result.assetUrl ?? result.releaseUrl;
    final UpdateInstaller? installer = _installer;
    if (url == null || installer == null) {
      return false;
    }
    try {
      await installer.install(url);
      return true;
    } on Object {
      return false;
    }
  }

  /// Picks the asset matching the current platform (overridable in tests
  /// via [assetSuffixFor]).
  _AssetMatch _pickAsset(List<Object?> assets) {
    final String suffix = assetSuffixFor?.call() ?? defaultAssetSuffix();
    for (final Object? asset in assets) {
      if (asset is! Map<String, Object?>) {
        continue;
      }
      final String name = (asset['name'] ?? '').toString().toLowerCase();
      final String url = (asset['browser_download_url'] ?? '').toString();
      if (suffix.isNotEmpty && name.endsWith(suffix) && url.isNotEmpty) {
        return _AssetMatch(name: name, url: url);
      }
    }
    return const _AssetMatch(name: null, url: null);
  }
}

class _AssetMatch {
  const _AssetMatch({required this.name, required this.url});

  final String? name;
  final String? url;
}

/// Numeric-aware, tolerant version compare: splits on non-alphanumerics,
/// compares numeric runs numerically and letters lexically. `v` prefixes
/// and build metadata (`+1`) are ignored. Returns <0 / 0 / >0 like
/// `compareTo`.
int compareVersions(String a, String b) {
  final List<String> left = _normalize(a);
  final List<String> right = _normalize(b);
  final int common = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < common; i++) {
    final int cmp = _comparePart(left[i], right[i]);
    if (cmp != 0) {
      return cmp;
    }
  }
  return left.length.compareTo(right.length);
}

List<String> _normalize(String version) {
  final String base = version.toLowerCase().split('+').first;
  final String trimmed =
      base.startsWith('v') ? base.substring(1) : base;
  return trimmed
      .split(RegExp(r'[^a-z0-9]+'))
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
}

int _comparePart(String a, String b) {
  final int? ai = int.tryParse(a);
  final int? bi = int.tryParse(b);
  if (ai != null && bi != null) {
    return ai.compareTo(bi);
  }
  return a.compareTo(b);
}
