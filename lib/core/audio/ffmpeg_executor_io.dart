/// IO arm of [FFmpegExecutor]: `ffmpeg_kit_flutter_new` (Android/iOS and
/// any platform where the plugin registers a native implementation).
///
/// Desktop note: the plugin's Dart API always compiles; without a native
/// registration `FFmpegKit.executeWithArgumentsAsync` rejects — the
/// rejection is caught and converted into a failed [FFmpegRunResult], so
/// feature code degrades gracefully (e.g. the cutter falls back to "save
/// without waveform preview").
library;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:wavely/core/audio/ffmpeg_executor.dart';

/// Production executor.
class FFmpegKitExecutor implements FFmpegExecutor {
  const FFmpegKitExecutor();

  /// Keep logs bounded — ebur128 summaries and error context fit easily.
  static const int _maxLogChars = 64 * 1024;

  @override
  bool get isAvailable => true;

  @override
  Future<FFmpegRunResult> execute(List<String> args) async {
    try {
      final session = await FFmpegKit.executeWithArgumentsAsync(args);
      final returnCode = await session.getReturnCode();
      final bool success = ReturnCode.isSuccess(returnCode);
      final String? logs = await session.getAllLogsAsString();
      return FFmpegRunResult(
        success: success,
        logs: logs == null || logs.isEmpty
            ? null
            : _truncate(logs),
      );
    } on Object catch (error) {
      return FFmpegRunResult(success: false, logs: error.toString());
    }
  }

  static String _truncate(String logs) => logs.length <= _maxLogChars
      ? logs
      : logs.substring(logs.length - _maxLogChars);
}
