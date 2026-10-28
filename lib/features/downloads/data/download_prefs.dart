import 'package:shared_preferences/shared_preferences.dart';

/// Download settings persisted in SharedPreferences (Stage 2.1 Section 10).
class DownloadPrefs {
  /// Creates prefs over [prefs].
  DownloadPrefs(this._prefs);

  static const String _kQuality = 'downloads.quality';
  static const String _kTemplate = 'downloads.folderTemplate';
  static const String _kWifiOnly = 'downloads.wifiOnly';
  static const String _kConcurrency = 'downloads.concurrency';
  static const String _kBaseDir = 'downloads.baseDir';

  final SharedPreferences _prefs;

  /// Requested quality: `320` | `flac` | `original` (default `original`).
  String get quality => _prefs.getString(_kQuality) ?? 'original';

  /// Folder template (default `Music/{continent}/{country}/{genre}`).
  String get folderTemplate =>
      _prefs.getString(_kTemplate) ?? FolderTemplateDefault;

  /// Wi-Fi-only gate (default true).
  bool get wifiOnly => _prefs.getBool(_kWifiOnly) ?? true;

  /// Max concurrent downloads, 1–5 (default 3 per spec).
  int get concurrency => _prefs.getInt(_kConcurrency) ?? 3;

  /// Storage root (empty = platform default music directory).
  String get baseDir => _prefs.getString(_kBaseDir) ?? '';

  /// Sets quality (`320` | `flac` | `original`).
  Future<void> setQuality(String v) => _prefs.setString(_kQuality, v);

  /// Sets the folder template.
  Future<void> setFolderTemplate(String v) =>
      _prefs.setString(_kTemplate, v);

  /// Sets the Wi-Fi-only gate.
  Future<void> setWifiOnly(bool v) => _prefs.setBool(_kWifiOnly, v);

  /// Sets concurrency, clamped to 1–5.
  Future<void> setConcurrency(int v) =>
      _prefs.setInt(_kConcurrency, v.clamp(1, 5));

  /// Sets the storage root (empty string = platform default).
  Future<void> setBaseDir(String v) => _prefs.setString(_kBaseDir, v);
}

/// Default template constant shared with [FolderTemplate.defaultTemplate]
/// (duplicated as a plain string so prefs need no import of the domain
/// class; both must stay in sync and the test suite asserts equality).
const String FolderTemplateDefault = 'Music/{continent}/{country}/{genre}';
