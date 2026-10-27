import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/features/library/data/library_scanner.dart';
import 'package:wavely/features/library/data/library_scanner_web.dart';

/// Web arm of the scanner binding (default of the conditional export in
/// `library_scanner_provider.dart`; the IO arm overrides it when
/// `dart.library.io` is available).
///
/// Web never builds the `ScanLibrary` usecase — browser sandboxing makes
/// recursive folder scans impossible, so the disabled web scanner is bound
/// directly (no `dart:io` anywhere in this arm).
final libraryScannerProvider = Provider<LibraryScanner>(
  (ref) => const WebLibraryScanner(),
);
