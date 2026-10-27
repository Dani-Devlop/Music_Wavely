import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/domain/usecases/scan_library.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/library_scanner_android.dart';
import 'package:wavely/features/library/data/library_scanner_desktop.dart';

/// IO-platform arm of the scanner binding (selected by the conditional
/// export in `library_scanner_provider.dart`).
///
/// The `ScanLibrary` usecase (and therefore `dart:io`) is only referenced
/// from this file, keeping the shared facade web-compilable.
final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  final db = ref.watch(databaseProvider);
  final scanLibrary = ScanLibrary(
    tracksDao: db.tracksDao,
    lyricsDao: db.lyricsDao,
  );
  final settingsStore = ref.watch(settingsStoreProvider);
  if (PlatformUtils.isDesktop) {
    return DesktopLibraryScanner(
      scanLibrary: scanLibrary,
      settingsStore: settingsStore,
    );
  }
  return MobileLibraryScanner(
    scanLibrary: scanLibrary,
    settingsStore: settingsStore,
  );
});
