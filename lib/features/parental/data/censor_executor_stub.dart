import 'package:wavely/features/parental/data/censor_service.dart';

/// Web (and any non-`dart:io`) arm of the censor executor.
///
/// KEEP IN SYNC with `censor_executor_io.dart` (identical public surface).
/// ffmpeg_kit_flutter_new is a native plugin and cannot run in browsers, so
/// the web executor simply throws — callers must catch and fall back to the
/// original file. This file keeps web builds compiling clean: no `dart:io`,
/// no ffmpeg_kit imports.
class FfmpegCensorExecutor implements AudioCensorExecutor {
  const FfmpegCensorExecutor();

  @override
  Future<Result<String?>> render({
    required String inputPath,
    required String outputPath,
    required List<(int, int)> muteRangesMs,
    required bool beepInsteadOfSilence,
  }) =>
      Future.error(
        UnsupportedError('audio censoring unsupported on web'),
      );
}

/// Web arm: browsers have no local filesystem, so nothing "exists".
Future<bool> localFileExists(String path) async => false;
