import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/usecases/scan_library.dart';
import 'package:wavely/features/library/data/library_scanner.dart';

/// Default resolver for the cover-art directory:
/// `<application documents>/covers`. Returns null when the directory cannot
/// be resolved (covers then stay disabled for the run).
Future<String?> defaultCoversDirResolver() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, AppConstants.coversDirName);
  } on Object catch (_) {
    return null;
  }
}

/// Desktop scanner (Windows / macOS / Linux).
///
/// Folder picking uses `file_picker`'s static [FilePicker.getDirectoryPath]
/// (one folder per invocation — the UI repeats the call as needed); scanning
/// delegates to the [ScanLibrary] usecase; folder watching uses a polling
/// snapshot watcher because `file_system` 2.x has no `Watcher` class.
class DesktopLibraryScanner extends LibraryScanner {
  /// Creates the desktop scanner.
  DesktopLibraryScanner({
    required ScanLibrary scanLibrary,
    required SettingsStore settingsStore,
    this.coversDirResolver = defaultCoversDirResolver,
  })  : _scanLibrary = scanLibrary,
        _folders = ScanFoldersStore(settingsStore);

  final ScanLibrary _scanLibrary;
  final ScanFoldersStore _folders;

  /// Resolves the cover directory before each scan (injectable for tests).
  final Future<String?> Function() coversDirResolver;

  @override
  Stream<ScanEvent> scan(List<String> folders) async* {
    final coversDir = await _safeCoversDir();
    yield* _scanLibrary.scan(folders: folders, coversDir: coversDir);
  }

  @override
  Future<List<String>> pickFolders() async {
    final path = await FilePicker.getDirectoryPath();
    return path == null ? const <String>[] : <String>[path];
  }

  @override
  Future<List<String>> watchFolders() => _folders.read();

  /// Emits [folder] whenever its recursive content snapshot (file count,
  /// newest mtime, total size) changed — at most once per
  /// [AppConstants.scanDebounceSeconds], so bursts of edits coalesce into
  /// one rescan signal.
  Stream<String> watch(String folder) => _PollingWatcher(folder).start();

  Future<String?> _safeCoversDir() async {
    try {
      return await coversDirResolver();
    } on Object catch (_) {
      return null;
    }
  }
}

/// Polling folder watcher.
///
/// Deviation note: the task allowed `file_system`'s `DirectoryWatcher`, but
/// file_system 2.0.9 ships no watcher API at all (verified against its API
/// docs), so change detection polls a lightweight snapshot on a
/// [Timer.periodic] whose period is the scan debounce interval. Snapshots
/// are taken synchronously to keep the timer callback simple.
class _PollingWatcher {
  _PollingWatcher(this._folder);

  static final Duration _interval = Duration(
    seconds: AppConstants.scanDebounceSeconds,
  );

  final String _folder;

  /// Starts polling; the returned stream emits the folder path on every
  /// detected change. Cancelling the subscription stops the timer.
  Stream<String> start() {
    late final StreamController<String> controller;
    var last = _snapshot();
    final timer = Timer.periodic(_interval, (_) {
      final current = _snapshot();
      if (current != null && current != last && !controller.isClosed) {
        controller.add(_folder);
      }
      if (current != null) {
        last = current;
      }
    });
    controller = StreamController<String>(
      onCancel: () {
        timer.cancel();
      },
    );
    return controller.stream;
  }

  /// Recursive content snapshot: (file count, max mtime ms, total size).
  ({int count, int maxMtimeMs, int totalSize})? _snapshot() {
    try {
      final dir = Directory(_folder);
      if (!dir.existsSync()) {
        return null;
      }
      var count = 0;
      var maxMtimeMs = 0;
      var totalSize = 0;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final stat = entity.statSync();
        count++;
        totalSize += stat.size;
        final mtimeMs = stat.modified.millisecondsSinceEpoch;
        if (mtimeMs > maxMtimeMs) {
          maxMtimeMs = mtimeMs;
        }
      }
      return (count: count, maxMtimeMs: maxMtimeMs, totalSize: totalSize);
    } on Object catch (_) {
      return null;
    }
  }
}
