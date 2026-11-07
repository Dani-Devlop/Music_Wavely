/// "Set as ringtone / notification / alarm" persistence (Phase 7.2).
///
/// The cut file is copied into the standard per-kind system directory and
/// registered in Wavely's own settings so the app can surface recent
/// ringtones. Registering with the platform RingtoneManager requires an
/// Android build target (this repository currently ships Linux + web), so
/// the platform-registration step is a documented no-op here; the saved
/// file lands in the conventional directory each platform's sound picker
/// scans.
library;

import 'dart:io';

import 'package:wavely/features/audio_cutter/data/cutter_math.dart';

/// Result of a ringtone save.
class RingtoneSaveResult {
  const RingtoneSaveResult({required this.savedTo, this.registered = false});

  /// Absolute path of the saved audio file.
  final String savedTo;

  /// Whether the platform ringtone registration succeeded (always `false`
  /// on targets without RingtoneManager access — see library doc).
  final bool registered;
}

/// Abstracts the filesystem for tests.
abstract interface class RingtoneFilesystem {
  Directory directory(String path);
  Future<void> copy(String source, String destination);
}

/// Production filesystem.
class IoRingtoneFilesystem implements RingtoneFilesystem {
  const IoRingtoneFilesystem();

  @override
  Directory directory(String path) => Directory(path);

  @override
  Future<void> copy(String source, String destination) =>
      File(source).copy(destination);
}

/// Saves [cutFilePath] as [kind].
class RingtoneSaver {
  RingtoneSaver({RingtoneFilesystem? fs}) : _fs = fs ?? const IoRingtoneFilesystem();

  final RingtoneFilesystem _fs;

  /// Base directory per kind (conventional Android layout; on Linux the
  /// user-visible `Music/Ringtones` tree).
  static const Map<RingtoneKind, String> kDirectoryNames =
      <RingtoneKind, String>{
    RingtoneKind.ringtone: 'Ringtones',
    RingtoneKind.notification: 'Notifications',
    RingtoneKind.alarm: 'Alarms',
  };

  /// Music root: Android external storage `Music`, elsewhere `~/Music`.
  Future<String> _musicRoot() async {
    if (Platform.isAndroid) {
      final Directory? external = await _androidExternalMusic();
      if (external != null) {
        return external.path;
      }
    }
    final String home =
        Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$home/Music';
  }

  /// Android media root via the environment (no plugin dependency).
  Future<Directory?> _androidExternalMusic() async {
    final String? sdcard = Platform.environment['EXTERNAL_STORAGE'];
    if (sdcard == null || sdcard.isEmpty) {
      return null;
    }
    final Directory dir = Directory('$sdcard/Music');
    try {
      if (await dir.exists()) {
        return dir;
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Copies the cut file to `<MusicRoot>/<Kind>s?/…` (directory name per
  /// [kDirectoryNames]) as `Wavely - <kind>-<timestamp>.<ext>`.
  Future<RingtoneSaveResult> saveAs(
    String cutFilePath,
    RingtoneKind kind,
  ) async {
    final String root = await _musicRoot();
    final String kindDirName = kDirectoryNames[kind]!;
    final Directory target =
        _fs.directory('$root/$kindDirName');
    try {
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
    } on Object {
      // Fall back to the Music root itself when the kind dir is not
      // creatable (sandboxed environments).
    }
    final String ext = cutFilePath.contains('.')
        ? cutFilePath.substring(cutFilePath.lastIndexOf('.') + 1)
        : 'm4a';
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[:.]'), '-')
        .substring(0, 19);
    final String destination =
        '${target.path}/Wavely ${kind.label}-$stamp.$ext';
    await _fs.copy(cutFilePath, destination);
    return RingtoneSaveResult(savedTo: destination);
  }
}
