/// Shared FFmpeg execution abstraction (Phase 7).
///
/// Pure argument-building stays in the feature layers; this hub only owns
/// "run these args, report success + logs". The IO arm wraps
/// `ffmpeg_kit_flutter_new` (same dependency the parental censor uses); the
/// stub arm keeps web builds clean.
library;

export 'ffmpeg_executor_stub.dart'
    if (dart.library.io) 'ffmpeg_executor_io.dart';

/// Outcome of one FFmpeg run.
class FFmpegRunResult {
  const FFmpegRunResult({required this.success, this.logs});

  final bool success;

  /// Combined session logs (truncated by the implementation) for error
  /// surfacing and the ebur128 loudness parser.
  final String? logs;
}

/// Executor contract: [FFmpegKitExecutor] (IO) and the web stub.
abstract interface class FFmpegExecutor {
  /// Runs [args] to completion. Never throws for ffmpeg-level failures;
  /// may throw only when the platform has no FFmpeg at all (stub arm).
  Future<FFmpegRunResult> execute(List<String> args);

  /// Whether this executor can actually run FFmpeg here. The IO arm
  /// reports the plugin's availability heuristically (desktop plugin-less
  /// runs fail on first execute, so this stays optimistic).
  bool get isAvailable;
}
