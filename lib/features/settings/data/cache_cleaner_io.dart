import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wavely/core/constants/app_constants.dart';

/// IO (Android/iOS/desktop) arm of the settings cache helpers.
///
/// KEEP IN SYNC with `cache_cleaner_stub.dart` (identical public surface).

/// Total size in bytes of the app's temporary directory. Any failure (e.g.
/// path_provider unavailable in tests) resolves to 0 so the settings row
/// always renders.
Future<int> appCacheSizeBytes() async {
  try {
    final dir = await getTemporaryDirectory();
    return _directorySize(dir);
  } on Object catch (_) {
    return 0;
  }
}

/// Deletes the temporary directory contents plus the covers directory under
/// the app documents folder ([AppConstants.coversDirName] — the scan
/// pipeline's cover-art cache). Returns a short human-readable result for
/// the settings SnackBar.
Future<String> clearAppCaches() async {
  var removed = 0;
  try {
    final temp = await getTemporaryDirectory();
    removed += _deleteContents(temp);
  } on Object catch (_) {
    // Temporary dir unreadable/unavailable — keep clearing covers.
  }
  try {
    final docs = await getApplicationDocumentsDirectory();
    final covers = Directory(
      p.join(docs.path, AppConstants.coversDirName),
    );
    removed += _deleteContents(covers);
  } on Object catch (_) {
    // Covers dir unreadable — report what was removed so far.
  }
  if (removed == 0) {
    return 'Cache is already empty.';
  }
  return 'Removed $removed file${removed == 1 ? '' : 's'}.';
}

int _directorySize(Directory dir) {
  var total = 0;
  for (final entry in dir.listSync(recursive: true, followLinks: false)) {
    if (entry is File) {
      try {
        total += entry.lengthSync();
      } on Object catch (_) {
        // Unreadable file contributes 0.
      }
    }
  }
  return total;
}

int _deleteContents(Directory dir) {
  if (!dir.existsSync()) {
    return 0;
  }
  var removed = 0;
  for (final entry in dir.listSync(recursive: false, followLinks: false)) {
    try {
      entry.deleteSync(recursive: true);
      removed++;
    } on Object catch (_) {
      // Locked/already-deleted entries are skipped.
    }
  }
  return removed;
}
