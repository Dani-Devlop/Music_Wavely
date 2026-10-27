/// Conditional-export hub for the settings cache helpers.
///
/// Same pattern as the `local_cover` trio: the default arm (web / anything
/// without `dart.library.io`) reports zeros and a friendly message, because
/// `path_provider`'s API surface is `dart:io`-typed and browsers have no
/// temporary directory to clear.
export 'cache_cleaner_stub.dart'
    if (dart.library.io) 'cache_cleaner_io.dart';
