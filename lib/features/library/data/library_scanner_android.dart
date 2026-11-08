import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/usecases/scan_library.dart';
import 'package:wavely/features/library/data/library_scanner.dart';

/// MethodChannel used by [AndroidUriPersister]; the patched Android shell
/// (tools/patch_android_media_store.py) answers with `false`, keeping the
/// Stage 1.1 "plain path" contract.
const MethodChannel _safChannel = MethodChannel('wavely/saf');

/// MethodChannel to the native MediaStore audio bridge.
///
/// Implemented by the patched Android shell
/// (tools/patch_android_media_store.py): `queryAudioTracks` returns every
/// music file the system indexer knows about and requests the media
/// permission on first use. On Android 10+ scoped storage this is the ONLY
/// reliable way to enumerate third-party audio — dart:io directory walking
/// is refused outside the app sandbox.
const MethodChannel _mediaStoreChannel = MethodChannel('wavely/media_store');

/// Persists Android SAF directory permissions for picked folders.
///
/// The patched shell answers `false` (no real SAF persistence), which keeps
/// the plain path on record; actual access goes through the MediaStore
/// bridge, so this remains a no-op compatibility stub.
@visibleForTesting
class AndroidUriPersister {
  AndroidUriPersister._();

  /// Tries to persist read access for [path]; returns false when no native
  /// handler is registered or the call fails.
  static Future<bool> persist(String path) async {
    try {
      final result = await _safChannel.invokeMethod<bool>(
        'persistUriPermission',
        <String, String>{'path': path},
      );
      return result ?? false;
    } on Object catch (_) {
      return false;
    }
  }
}

/// Result payload of the native MediaStore audio query.
@visibleForTesting
typedef AndroidMediaStoreResult = ({bool granted, List<String> paths});

/// Keeps only the MediaStore paths living under one of [folders] (prefix
/// match against the canonical DATA column paths). An empty [folders] list
/// scans the whole device library. Trailing separators on [folders] are
/// normalized so `/music` does not accidentally match `/music-box/…`.
@visibleForTesting
List<String> androidMediaStorePathsUnderFolders(
  List<String> paths,
  List<String> folders,
) {
  if (folders.isEmpty) {
    return List<String>.of(paths);
  }
  final normalized = <String>[
    for (final folder in folders)
      folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder,
  ];
  return <String>[
    for (final path in paths)
      if (normalized.any((folder) => path.startsWith('$folder/'))) path,
  ];
}

/// Mobile scanner (Android / iOS).
///
/// Android: folder picking uses SAF via `FilePicker.getDirectoryPath` (one
/// folder per invocation); scanning enumerates audio through the MediaStore
/// bridge and filters the rows against the picked folders, so scoped
/// storage never blocks detection. When the native bridge is unavailable
/// (un-patched shell, tests) the scanner falls back to the classic
/// filesystem walk.
///
/// iOS (and the fallback path): scanning delegates to the [ScanLibrary]
/// usecase directly.
class MobileLibraryScanner extends LibraryScanner {
  /// Creates the mobile scanner.
  MobileLibraryScanner({
    required ScanLibrary scanLibrary,
    required SettingsStore settingsStore,
  })  : _scanLibrary = scanLibrary,
        _folders = ScanFoldersStore(settingsStore);

  final ScanLibrary _scanLibrary;
  final ScanFoldersStore _folders;

  @override
  Stream<ScanEvent> scan(List<String> folders) async* {
    // v1.0.1-beta3 fix (owner report: "NO ALBUM ART"): embedded covers are
    // extracted to the app documents covers dir on EVERY mobile scan path.
    // The previous build dropped [coversDir] here, so [Track.coverPath]
    // stayed null on Android and every row degraded to the fallback art.
    final coversDir = await _safeCoversDir();
    if (Platform.isAndroid) {
      final mediaStore = await _queryMediaStore();
      if (mediaStore != null) {
        if (!mediaStore.granted) {
          yield const ScanEvent.error(
            file: 'MediaStore',
            reason: 'Music and audio permission denied — grant Wavely access '
                'in system settings, then scan again.',
          );
          yield const ScanEvent.completed(count: 0, errors: <String>[]);
          return;
        }
        yield* _scanLibrary.scanFilePaths(
          paths: androidMediaStorePathsUnderFolders(mediaStore.paths, folders),
          coversDir: coversDir,
        );
        return;
      }
      // No native bridge (un-patched shell / tests): fall through to the
      // filesystem walk below.
    }
    // The usecase handles cover extraction internally; covers go to the app
    // documents directory (resolved above).
    yield* _scanLibrary.scan(folders: folders, coversDir: coversDir);
  }

  /// App-documents `covers/` directory (created on demand); null when the
  /// platform does not expose a documents dir (web) so the usecase skips
  /// cover writing entirely.
  Future<String?> _safeCoversDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, AppConstants.coversDirName));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return dir.path;
    } on Object {
      return null;
    }
  }

  @override
  Future<List<String>> pickFolders() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) {
      return const <String>[];
    }
    // Fire-and-forget: a missing native handler simply keeps the plain
    // path.
    unawaited(AndroidUriPersister.persist(path));
    return <String>[path];
  }

  @override
  Future<List<String>> watchFolders() => _folders.read();

  /// Queries the native MediaStore bridge. Returns null when the channel is
  /// not implemented on this platform (so callers can use the fallback).
  Future<AndroidMediaStoreResult?> _queryMediaStore() async {
    try {
      final result = await _mediaStoreChannel
          .invokeMethod<Object?>('queryAudioTracks')
          .timeout(const Duration(seconds: 30));
      if (result is! Map) {
        return null;
      }
      final granted = result['granted'] == true;
      final rows = result['tracks'];
      final paths = <String>[
        if (rows is List)
          for (final row in rows)
            if (row is Map && row['path'] is String) row['path']! as String,
      ];
      return (granted: granted, paths: paths);
    } on Object catch (_) {
      // MissingPluginException (tests, iOS), timeout, or a decoding
      // problem — the caller falls back to the filesystem walk.
      return null;
    }
  }
}
