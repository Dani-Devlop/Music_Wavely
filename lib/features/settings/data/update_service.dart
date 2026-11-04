import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'package:wavely/features/settings/data/update_platform.dart';

/// Progress of a platform download, in bytes (`total` is `null` when the
/// server does not advertise a content length).
typedef UpdateProgressCallback = void Function(int received, int? total);

/// Outcome of handing a release to the platform installer.
///
/// The sealed hierarchy mirrors what the UI can react to: a native updater
/// took over, the binary was replaced in place (Linux AppImage), the
/// release page opened in the browser, or the attempt failed with a
/// message the user can act on.
sealed class UpdateInstallOutcome {
  /// Creates the outcome.
  const UpdateInstallOutcome();
}

/// A native updater UI took over: WinSparkle on Windows (fed by the
/// release `appcast.xml`) or the Android package-installer prompt opened
/// via `open_filex`.
final class UpdaterUiLaunched extends UpdateInstallOutcome {
  /// Creates the outcome.
  const UpdaterUiLaunched();
}

/// The running Linux AppImage was replaced in place and a detached
/// relaunch of the new build is scheduled.
final class AppImageReplaced extends UpdateInstallOutcome {
  /// Creates the outcome.
  const AppImageReplaced();
}

/// The release page opened in the external browser (web/iOS fallback and
/// the honest last resort when no installable asset matches).
final class OpenedReleasePage extends UpdateInstallOutcome {
  /// Creates the outcome.
  const OpenedReleasePage();
}

/// The install attempt failed with a human-readable [message].
final class InstallFailed extends UpdateInstallOutcome {
  /// Creates the outcome.
  const InstallFailed(this.message);

  /// Why the install could not proceed.
  final String message;
}

/// Result of an update check against GitHub Releases.
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.updateAvailable,
    required this.currentVersion,
    this.latestVersion,
    this.releaseUrl,
    this.releaseNotes,
    this.publishedAt,
    this.assetUrl,
    this.assetName,
    this.assetSizeBytes,
  });

  /// Up-to-date marker.
  factory UpdateCheckResult.upToDate(String currentVersion) =>
      UpdateCheckResult._(
        updateAvailable: false,
        currentVersion: currentVersion,
      );

  /// An installable release is available.
  factory UpdateCheckResult.available({
    required String currentVersion,
    required String latestVersion,
    required String releaseUrl,
    String? releaseNotes,
    DateTime? publishedAt,
    String? assetUrl,
    String? assetName,
    int? assetSizeBytes,
  }) =>
      UpdateCheckResult._(
        updateAvailable: true,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseUrl: releaseUrl,
        releaseNotes: releaseNotes,
        publishedAt: publishedAt,
        assetUrl: assetUrl,
        assetName: assetName,
        assetSizeBytes: assetSizeBytes,
      );

  final bool updateAvailable;
  final String currentVersion;
  final String? latestVersion;

  /// HTML page of the release (opened in a browser when no asset fits).
  final String? releaseUrl;

  /// Release notes body from GitHub (markdown), shown in the update UI.
  final String? releaseNotes;

  /// When the release was published (GitHub `published_at`).
  final DateTime? publishedAt;

  /// Direct download URL of the asset matching the running platform.
  final String? assetUrl;
  final String? assetName;

  /// Size of the matching asset in bytes (download progress denominator).
  final int? assetSizeBytes;
}

/// Platform install seam. Tests inject a recorder; the production binding
/// is built by `createPlatformInstaller()` (conditional import: the real
/// flows on IO platforms, the release-page fallback on web).
abstract interface class UpdateInstaller {
  /// Installs (or surfaces) the given release through its platform flow.
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  });
}

/// Auto-update service over the GitHub Releases API (Stage 7).
///
/// - `checkForUpdate()` resolves the latest release for
///   `Dani-Devlop/Music_Wavely` and picks the asset matching the running
///   platform: per-ABI APK (falling back to universal) on Android, `.msix`
///   (falling back to `.zip`) on Windows, `.AppImage` on Linux.
/// - Version comparison uses `pub_semver` (numeric-aware, `v` prefixes
///   and build metadata ignored: `v1.0.1` == `1.0.1+5`).
/// - Never throws: failures surface as a "check failed" (up-to-date)
///   result so the settings UI cannot crash on a flaky network.
class UpdateService {
  /// Creates the service.
  ///
  /// [currentVersion] defaults to the compile-time `APP_VERSION` define
  /// (wired in tests); [releasesApi] targets the owner's repo;
  /// [assetSuffixFor] overrides the platform-asset picker in tests;
  /// [androidAbi] pins the device ABI (else `deviceAbi()` is consulted on
  /// Android only).
  UpdateService({
    http.Client? client,
    String? currentVersion,
    Uri? releasesApi,
    UpdateInstaller? installer,
    String Function()? assetSuffixFor,
    String? androidAbi,
  })  : _client = client ?? http.Client(),
        _currentVersion = currentVersion ?? const String.fromEnvironment('APP_VERSION'),
        _releasesApi = releasesApi ?? Uri.https(
          'api.github.com',
          '/repos/Dani-Devlop/Music_Wavely/releases/latest',
        ),
        _installer = installer,
        androidAbi = androidAbi,
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

  /// Pinned device ABI (test seam; `null` → resolve on Android only).
  final String? androidAbi;

  /// Checks GitHub for a newer release. Never throws.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      // Stage 3 audit (SEC-5): bound the update check so a stalled GitHub
      // response cannot hang the settings UI.
      final response = await _client
          .get(
            _releasesApi,
            headers: const <String, String>{
              'accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final String tagName = (decoded['tag_name'] ?? '').toString();
      final String htmlUrl = (decoded['html_url'] ?? releasesPage).toString();
      if (tagName.isEmpty ||
          compareVersions(_currentVersion, tagName) >= 0) {
        return UpdateCheckResult.upToDate(_currentVersion);
      }
      final assets =
          decoded['assets'] is List ? decoded['assets'] as List<Object?> : const <Object?>[];
      final _AssetMatch match = await _pickAsset(assets);
      return UpdateCheckResult.available(
        currentVersion: _currentVersion,
        latestVersion: tagName,
        releaseUrl: htmlUrl,
        releaseNotes: _notesOf(decoded),
        publishedAt: _publishedAtOf(decoded),
        assetUrl: match.url,
        assetName: match.name,
        assetSizeBytes: match.sizeBytes,
      );
    } on Object {
      return UpdateCheckResult.upToDate(_currentVersion);
    }
  }

  /// Hands the release to the platform installer (Stage 7 flows:
  /// WinSparkle/MSIX on Windows, AppImage self-replace on Linux, APK +
  /// package-installer prompt on Android, release page on web/iOS).
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    final UpdateInstaller? installer = _installer;
    if (!result.updateAvailable) {
      return const InstallFailed('No update to install.');
    }
    if (installer == null) {
      return const InstallFailed('No installer is configured.');
    }
    try {
      return await installer.install(result, onProgress: onProgress);
    } on Object catch (error) {
      return InstallFailed('Update failed: $error');
    }
  }

  /// Picks the asset matching the current platform (overridable in tests
  /// via [assetSuffixFor]); Android prefers the device-ABI APK split over
  /// the universal bundle, Windows prefers the MSIX over the ZIP.
  Future<_AssetMatch> _pickAsset(List<Object?> assets) async {
    final String suffix = assetSuffixFor?.call() ?? defaultAssetSuffix();
    if (suffix == '.apk') {
      final String? abi = androidAbi ?? await deviceAbi();
      if (abi != null && abi.isNotEmpty) {
        final _AssetMatch split = _matchAsset(
          assets,
          (String name) => name.endsWith('.apk') && name.contains('android-$abi'),
        );
        if (split.url != null) {
          return split;
        }
      }
      return _matchAsset(
        assets,
        (String name) => name.endsWith('.apk') && name.contains('universal'),
      );
    }
    if (suffix == '.msix') {
      final _AssetMatch msix =
          _matchAsset(assets, (String name) => name.endsWith('.msix'));
      if (msix.url != null) {
        return msix;
      }
      return _matchAsset(assets, (String name) => name.endsWith('.zip'));
    }
    return _matchAsset(
      assets,
      (String name) => suffix.isNotEmpty && name.endsWith(suffix),
    );
  }

  _AssetMatch _matchAsset(
    List<Object?> assets,
    bool Function(String name) predicate,
  ) {
    for (final asset in assets) {
      if (asset is! Map<String, Object?>) {
        continue;
      }
      final name = (asset['name'] ?? '').toString().toLowerCase();
      final url = (asset['browser_download_url'] ?? '').toString();
      if (url.isNotEmpty && predicate(name)) {
        final size = asset['size'] is int ? asset['size'] as int? : null;
        return _AssetMatch(name: name, url: url, sizeBytes: size);
      }
    }
    return const _AssetMatch();
  }

  static String? _notesOf(Map<String, Object?> decoded) {
    final String body = (decoded['body'] ?? '').toString();
    return body.isEmpty ? null : body;
  }

  static DateTime? _publishedAtOf(Map<String, Object?> decoded) {
    final String raw = (decoded['published_at'] ?? '').toString();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}

class _AssetMatch {
  const _AssetMatch({this.name, this.url, this.sizeBytes});

  final String? name;
  final String? url;
  final int? sizeBytes;
}

/// Numeric-aware version compare over `pub_semver`: tolerant of `v`
/// prefixes, build metadata (`+5`) and short forms (`2.0` → `2.0.0`).
/// Unparseable inputs fall back to a case-insensitive string compare.
/// Returns <0 / 0 / >0 like `compareTo`.
int compareVersions(String a, String b) {
  final Version? left = parseAppVersion(a);
  final Version? right = parseAppVersion(b);
  if (left == null || right == null) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
  return left.compareTo(right);
}

/// Parses `v1.2.3`, `1.2.3+5` and `1.2` into a `pub_semver` [Version].
/// Build metadata is dropped (release tags never carry a build number, so
/// `1.0.1+5` and `v1.0.1` must compare equal). Returns `null` when no
/// numeric component can be extracted.
Version? parseAppVersion(String raw) {
  var text = raw.trim().toLowerCase();
  final int plus = text.indexOf('+');
  if (plus >= 0) {
    text = text.substring(0, plus);
  }
  if (text.startsWith('v')) {
    text = text.substring(1);
  }
  final parts = <int>[
    for (final piece in text.split(RegExp(r'[^0-9]+')))
      if (piece.isNotEmpty) int.tryParse(piece) ?? -1,
  ];
  if (parts.isEmpty || parts.any((int part) => part < 0)) {
    return null;
  }
  while (parts.length < 3) {
    parts.add(0);
  }
  try {
    return Version(parts[0], parts[1], parts[2]);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
