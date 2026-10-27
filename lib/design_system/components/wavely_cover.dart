/// Conditional-export hub for local cover art inside the design system.
///
/// IO platforms resolve file-backed image providers; the web arm returns
/// null so callers fall back to their gradient-initial placeholder (the
/// browser sandbox cannot read local file paths).
export 'wavely_cover_stub.dart' if (dart.library.io) 'wavely_cover_io.dart';
