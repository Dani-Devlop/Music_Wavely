/// Web arm of the settings cache helpers (`cache_cleaner.dart` hub).
///
/// No `dart:io` here: browsers have no temporary directory owned by the app,
/// so the settings screen shows zero and a clear-cache confirmation reports
/// the feature as unavailable. KEEP IN SYNC with `cache_cleaner_io.dart`
/// (identical public surface).

/// Total size in bytes of the app cache (always 0 on web).
Future<int> appCacheSizeBytes() async => 0;

/// Clears the app cache; always reports "unavailable" on web.
Future<String> clearAppCaches() async =>
    'Cache clearing is unavailable on web.';
