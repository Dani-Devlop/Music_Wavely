/// Web (and any non-`dart:io`) arm of [FFmpegExecutor].
///
/// KEEP IN SYNC with `ffmpeg_executor_io.dart` (identical public surface).
/// ffmpeg_kit_flutter_new is a native plugin and cannot run in browsers.
library;

import 'package:wavely/core/audio/ffmpeg_executor.dart';

/// Web executor: every run fails with a clear message.
class FFmpegKitExecutor implements FFmpegExecutor {
  const FFmpegKitExecutor();

  @override
  bool get isAvailable => false;

  @override
  Future<FFmpegRunResult> execute(List<String> args) async =>
      const FFmpegRunResult(
        success: false,
        logs: 'FFmpeg is not available on this platform',
      );
}
