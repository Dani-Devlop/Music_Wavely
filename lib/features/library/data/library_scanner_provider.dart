/// Binding for the platform [LibraryScanner] implementation.
///
/// Conditional export (same pattern as the `local_cover` trio):
/// - default (web / anything without `dart.library.io`):
///   `library_scanner_provider_web.dart` — binds the disabled web scanner.
/// - `dart.library.io` (Android/iOS/desktop):
///   `library_scanner_provider_io.dart` — binds the mobile/desktop scanner
///   over the `ScanLibrary` usecase.
///
/// Consumers import this single file for `libraryScannerProvider`; the
/// scanner facade + `ScanFoldersStore` stay in `library_scanner.dart`.
export 'library_scanner_provider_web.dart'
    if (dart.library.io) 'library_scanner_provider_io.dart';
