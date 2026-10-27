import 'dart:convert';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Platform-independent library scanner facade.
///
/// Implementations live next to this file:
/// - `DesktopLibraryScanner` in `library_scanner_desktop.dart` (Windows/
///   macOS/Linux)
/// - `MobileLibraryScanner` in `library_scanner_android.dart` (Android/iOS)
/// - `WebLibraryScanner` in `library_scanner_web.dart` (scanning disabled)
///
/// This file must stay free of `dart:io` (the concrete scanners and the
/// `ScanLibrary` usecase import it) so web builds can still compile the
/// facade. The [libraryScannerProvider] binding therefore lives behind the
/// conditional import in `library_scanner_provider.dart`.
abstract class LibraryScanner {
  const LibraryScanner();

  /// Scans all [folders] recursively, emitting [ScanEvent]s. The stream never
  /// throws and always ends with a [ScanCompleted] event.
  Stream<ScanEvent> scan(List<String> folders);

  /// Opens a native folder picker; returns the picked folder(s) or an empty
  /// list when the user cancelled.
  Future<List<String>> pickFolders();

  /// The folders persisted for scanning (survives restarts via
  /// [SettingsStore]).
  Future<List<String>> watchFolders();
}

/// Persists the list of scan folders in the [SettingsStore] as a JSON string
/// under [AppConstants.settingsKeyPrefix] + `scanFolders`.
class ScanFoldersStore {
  /// Binds the store to a [SettingsStore] implementation.
  const ScanFoldersStore(this._settings);

  static const String _key = '${AppConstants.settingsKeyPrefix}scanFolders';

  final SettingsStore _settings;

  /// Reads the persisted folders; corrupt payloads resolve to an empty list
  /// instead of surfacing a storage failure to read-only callers.
  ///
  /// Dual-format tolerance (Task B wiring): the settings screen persists the
  /// same key as a `StringList` (canonical AppSettings writer), while this
  /// store historically wrote a JSON string — both are accepted so the two
  /// flows stay interoperable.
  Future<List<String>> read() async {
    final stored = await _settings.read<List<String>>(_key);
    if (stored != null) {
      return stored;
    }
    final raw = await _settings.read<String>(_key);
    if (raw == null) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList(growable: false);
    } on Object catch (_) {
      return const <String>[];
    }
  }

  /// Persists [folders].
  Future<void> write(List<String> folders) =>
      _settings.write(_key, jsonEncode(folders));
}
