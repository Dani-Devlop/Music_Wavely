import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/features/downloads/data/download_notifier.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/domain/folder_template.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/sources/source_providers.dart';

/// SharedPreferences-backed download settings.
final downloadPrefsProvider = Provider<DownloadPrefs>((ref) {
  return DownloadPrefs(ref.watch(sharedPrefsProvider));
});

/// Platform storage root: the user-configured directory when set, else the
/// system music/downloads directory.
final downloadsBaseDirProvider = Provider<Future<String> Function()>((ref) {
  return () async {
    final DownloadPrefs prefs = ref.watch(downloadPrefsProvider);
    final String configured = prefs.baseDir;
    if (configured.isNotEmpty) {
      return configured;
    }
    try {
      final Directory? dir = await getMusicDir();
      return dir?.path ?? (await getTemporaryDirectory()).path;
    } on Object {
      // Web / unsupported platforms: downloads will fail at file-IO time
      // with the documented UnsupportedError.
      return '/wavely-downloads';
    }
  };
});

Future<Directory?> getMusicDir() async {
  final Directory? base = await getDownloadsDirectory();
  return base;
}

/// Connectivity probe for the Wi-Fi-only gate (true = usable network).
final isUnmeteredProvider = Provider<Future<bool> Function()>((ref) {
  return () async {
    try {
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } on Object {
      return true;
    }
  };
});

/// Local notification wrapper (degrades to no-op when the channel fails).
final downloadNotifierProvider = Provider<DownloadNotifier>((ref) {
  return LocalDownloadNotifier();
});

/// The download manager singleton. Created lazily; `start()` runs the
/// boot-time repair on first access. Template/prefs changes apply on the
/// next container rebuild (documented in the Stage 2.1 report).
final downloadServiceProvider = FutureProvider<DownloadService>((ref) async {
  final DownloadService service = DownloadService(
    db: ref.watch(databaseProvider),
    prefs: ref.watch(downloadPrefsProvider),
    resolveSources: () => ref.read(enabledSourcesProvider.future),
    baseDir: ref.watch(downloadsBaseDirProvider),
    notifier: ref.watch(downloadNotifierProvider),
    folderTemplate: FolderTemplate(
      template: ref.read(downloadPrefsProvider).folderTemplate,
    ),
    isUnmetered: ref.watch(isUnmeteredProvider),
  );
  ref.onDispose(service.dispose);
  await service.start();
  return service;
});
