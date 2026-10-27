/// Conditional-export hub for the parental-control audio censor adapter.
///
/// Same pattern as the `cache_cleaner` trio: the default arm (web / anything
/// without `dart.library.io`) returns a graceful failure instead of touching
/// `ffmpeg_kit_flutter_new` or `dart:io`, keeping web builds clean.
///
/// Exposes [FfmpegCensorExecutor] (production [AudioCensorExecutor]) and the
/// [localFileExists] probe used by [CensorService].
library;

export 'censor_executor_stub.dart'
    if (dart.library.io) 'censor_executor_io.dart';
export 'censor_service.dart' show AudioCensorExecutor;
