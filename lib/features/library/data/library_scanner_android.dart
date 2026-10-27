import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/usecases/scan_library.dart';
import 'package:wavely/features/library/data/library_scanner.dart';

/// MethodChannel used by [AndroidUriPersister]; a matching native handler is
/// added when the Android shell is generated (Stage 1.1 records plain paths
/// only, so a missing handler degrades to `false`).
const MethodChannel _safChannel = MethodChannel('wavely/saf');

/// Persists Android SAF directory permissions for picked folders.
///
/// Stage 1.1 limitation: `FilePicker.getDirectoryPath` returns a plain file
/// path; on Android 11+ broad access to picked directories needs a
/// persisted `takePersistableUriPermission` call, which requires a platform
/// channel. This stub keeps the Dart side compile-clean and functional for
/// app-accessible paths; the native side lands with the Android shell.
@visibleForTesting
class AndroidUriPersister {
  AndroidUriPersister._();

  /// Tries to persist read access for [path]; returns false when no native
  /// handler is registered (the normal case in Stage 1.1) or the call fails.
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

/// Mobile scanner (Android / iOS).
///
/// Folder picking uses SAF via `FilePicker.getDirectoryPath` (one folder per
/// invocation); scanning delegates to the [ScanLibrary] usecase. Persisted
/// URI permissions are best-effort through [AndroidUriPersister] — see the
/// class docs for the Stage 1.1 limitation.
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
    // The usecase handles cover extraction internally; on mobile covers go
    // to the app documents directory (resolved there in Task 4's
    // composition root when path availability is guaranteed).
    yield* _scanLibrary.scan(folders: folders, coversDir: null);
  }

  @override
  Future<List<String>> pickFolders() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) {
      return const <String>[];
    }
    // Fire-and-forget: missing native handler simply keeps the plain path.
    unawaited(AndroidUriPersister.persist(path));
    return <String>[path];
  }

  @override
  Future<List<String>> watchFolders() => _folders.read();
}
