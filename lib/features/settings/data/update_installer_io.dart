import 'dart:async';
import 'dart:io' show Directory, File, Platform, Process, ProcessStartMode, exit;

import 'package:auto_updater/auto_updater.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/features/settings/data/update_service.dart';

/// Native install flows (Stage 7):
///
/// - **Windows** — WinSparkle via `auto_updater` against the release
///   `appcast.xml` (graceful download + install with its own UI). On any
///   Sparkle failure (plugin missing, feed absent, event timeout) the
///   flow falls back to downloading the MSIX and handing it to the
///   Windows App Installer.
/// - **Linux** — when running as an AppImage: download the new AppImage
///   next to the running one, `chmod +x`, atomically replace it (the
///   mounted squashfs keeps the old inode alive until exit) and relaunch
///   detached. Otherwise: open the release page.
/// - **Android** — download the APK into the app-specific downloads
///   directory with progress, then trigger the system package installer
///   via `open_filex` (REQUEST_INSTALL_PACKAGES is declared by
///   `tools/patch_android_media_store.py`).
/// - **iOS / macOS / others** — open the release page in the browser.
final class IoUpdateInstaller implements UpdateInstaller {
  /// Creates the IO installer over an optional [linkLauncher] (tests
  /// inject a recorder; the default opens real external URLs).
  IoUpdateInstaller({LinkLauncher? linkLauncher})
      : _launcher = linkLauncher ?? const UrlLinkLauncher();

  final LinkLauncher _launcher;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      // receiveTimeout bounds the idle time between stream chunks, not
      // the whole transfer — release assets exceed 100 MB.
      receiveTimeout: const Duration(minutes: 2),
    ),
  );

  /// WinSparkle feed: the release job stages `appcast.xml` next to the
  /// other assets, so this URL always resolves to the latest published
  /// release without shipping a feed URL per version.
  static const String _windowsAppcastUrl =
      'https://github.com/Dani-Devlop/Music_Wavely/releases/latest/download/appcast.xml';

  @override
  Future<UpdateInstallOutcome> install(
    UpdateCheckResult result, {
    UpdateProgressCallback? onProgress,
  }) async {
    try {
      if (Platform.isWindows) {
        return await _installWindows(result, onProgress);
      }
      if (Platform.isLinux) {
        return await _installLinux(result, onProgress);
      }
      if (Platform.isAndroid) {
        return await _installAndroid(result, onProgress);
      }
    } on Object catch (error) {
      return InstallFailed('Update failed: $error');
    }
    return await _openReleasePage(result);
  }

  /// Streams [url] into the temp directory and returns the saved path.
  Future<String> _download(
    String url, {
    required String fileName,
    UpdateProgressCallback? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = p.join(dir.path, 'wavely-update-$fileName');
    await _dio.download(url, savePath, onReceiveProgress: onProgress);
    return savePath;
  }

  // -- Windows ---------------------------------------------------------------

  Future<UpdateInstallOutcome> _installWindows(
    UpdateCheckResult result,
    UpdateProgressCallback? onProgress,
  ) async {
    if (await _tryWindowsSparkle()) {
      return const UpdaterUiLaunched();
    }
    final assetUrl = result.assetUrl;
    if (assetUrl == null) {
      return await _openReleasePage(result);
    }
    final path = await _download(
      assetUrl,
      fileName: _safeFileName(result.assetName, fallback: 'wavely-update.msix'),
      onProgress: onProgress,
    );
    final open = (await OpenFilex.open(path)).type;
    if (open != ResultType.done) {
      return InstallFailed('Windows installer could not be opened ($open).');
    }
    return const UpdaterUiLaunched();
  }

  /// Runs one WinSparkle check with UI. Returns `true` when Sparkle took
  /// over (update found/downloaded), `false` on not-available, error,
  /// silence or any plugin failure — every `false` leads to the in-app
  /// MSIX fallback.
  Future<bool> _tryWindowsSparkle() async {
    try {
      final settled = Completer<bool>();
      final listener = _SparkleListener((event) {
        if (settled.isCompleted) {
          return;
        }
        switch (event) {
          case 'available':
          case 'downloaded':
          case 'before-quit':
            settled.complete(true);
          case 'not-available':
          case 'error':
            settled.complete(false);
          case 'checking':
            break;
        }
      });
      autoUpdater.addListener(listener);
      try {
        await autoUpdater.setFeedURL(_windowsAppcastUrl);
        await autoUpdater.checkForUpdates();
        return await settled.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () => false,
        );
      } finally {
        autoUpdater.removeListener(listener);
      }
    } on Object {
      // MissingPluginException on non-Windows runners, WinSparkle init
      // failure, feed errors — the MSIX fallback covers all of them.
      return false;
    }
  }

  // -- Linux -------------------------------------------------------------------

  Future<UpdateInstallOutcome> _installLinux(
    UpdateCheckResult result,
    UpdateProgressCallback? onProgress,
  ) async {
    final appImagePath = Platform.environment['APPIMAGE'];
    final assetUrl = result.assetUrl;
    final isAppImageAsset =
        (result.assetName ?? '').toLowerCase().endsWith('.appimage');
    if (appImagePath == null || assetUrl == null || !isAppImageAsset) {
      // Not running from an AppImage (tar.gz/dev checkout) or no direct
      // asset — self-replacement is not safe; surface the release page.
      return await _openReleasePage(result);
    }
    final staged = File(
      p.join(
        File(appImagePath).parent.path,
        '.wavely-update-${DateTime.now().millisecondsSinceEpoch}.AppImage',
      ),
    );
    await _dio.download(assetUrl, staged.path, onReceiveProgress: onProgress);
    // The AppImage runtime needs the executable bit (the download drops
    // it); the staged file lives in the same directory as the running
    // image, so the rename below is an atomic same-filesystem move.
    await Process.run('chmod', <String>['+x', staged.path]);
    await staged.rename(appImagePath);
    await Process.start(
      appImagePath,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    // Give the screen a beat to show "restarting", then hand the process
    // over to the freshly launched build.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        exit(0);
      }),
    );
    return const AppImageReplaced();
  }

  // -- Android -----------------------------------------------------------------

  Future<UpdateInstallOutcome> _installAndroid(
    UpdateCheckResult result,
    UpdateProgressCallback? onProgress,
  ) async {
    final assetUrl = result.assetUrl;
    if (assetUrl == null) {
      return await _openReleasePage(result);
    }
    final dir = await _androidDownloadDir();
    final savePath = p.join(
      dir.path,
      _safeFileName(result.assetName, fallback: 'wavely-update.apk'),
    );
    await _dio.download(assetUrl, savePath, onReceiveProgress: onProgress);
    final open = (await OpenFilex.open(
      savePath,
      type: 'application/vnd.android.package-archive',
    ))
        .type;
    if (open != ResultType.done) {
      return InstallFailed('Android installer could not be opened ($open).');
    }
    return const UpdaterUiLaunched();
  }

  /// App-specific external downloads directory: writable without any
  /// storage permission (scoped storage), visible to the package
  /// installer through open_filex's FileProvider. Falls back to the temp
  /// directory when the platform channel is unavailable.
  Future<Directory> _androidDownloadDir() async {
    try {
      final dirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (dirs != null && dirs.isNotEmpty) {
        return dirs.first;
      }
    } on Object {
      // fall through to the temp directory
    }
    return await getTemporaryDirectory();
  }

  // -- Shared ------------------------------------------------------------------

  Future<UpdateInstallOutcome> _openReleasePage(
    UpdateCheckResult result,
  ) async {
    final url = Uri.parse(result.releaseUrl ?? UpdateService.releasesPage);
    await _launcher.launchExternal(url);
    return const OpenedReleasePage();
  }

  static String _safeFileName(String? candidate, {required String fallback}) {
    final name = (candidate ?? '').trim();
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      return fallback;
    }
    return name;
  }
}

/// Bridge from the auto_updater event stream to a one-shot completer.
final class _SparkleListener extends UpdaterListener {
  _SparkleListener(this.onEvent);

  final void Function(String event) onEvent;

  @override
  void onUpdaterError(UpdaterError? error) => onEvent('error');

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) => onEvent('checking');

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) =>
      onEvent('available');

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) =>
      onEvent('not-available');

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) =>
      onEvent('downloaded');

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) =>
      onEvent('before-quit');
}

/// Builds the platform update installer (IO variant: real flows).
UpdateInstaller createPlatformInstaller({LinkLauncher? linkLauncher}) =>
    IoUpdateInstaller(linkLauncher: linkLauncher);
