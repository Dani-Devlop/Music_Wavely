/// Conditional-export hub for `File` in domain contracts.
///
/// [SourceProvider.download] is io-only by nature (Stage 1.1 has no source
/// implementations, so the web arm ships a compile-only stub that throws if
/// ever used at runtime).
export 'source_file_stub.dart' if (dart.library.io) 'source_file_io.dart';
