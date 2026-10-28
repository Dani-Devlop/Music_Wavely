import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/parental/data/censor_service.dart';

/// IO (Android/iOS/macOS/desktop) arm: renders censored audio with
/// `ffmpeg_kit_flutter_new`.
///
/// Threading: [FFmpegKit.executeWithArgumentsAsync] already runs on its own
/// native thread, so this class does NOT spawn an [Isolate]. There is no
/// progress callback in v1 — a track render is a one-shot await; progress
/// UI is a later pass (session.getStatistics exists if needed).
class FfmpegCensorExecutor implements AudioCensorExecutor {
  const FfmpegCensorExecutor();

  @override
  Future<Result<String?>> render({
    required String inputPath,
    required String outputPath,
    required List<(int, int)> muteRangesMs,
    required bool beepInsteadOfSilence,
  }) async {
    if (muteRangesMs.isEmpty) {
      return const Result<String?>.success(null);
    }
    try {
      final args = <String>[
        '-y',
        '-i',
        inputPath,
        '-filter_complex',
        _filterGraph(muteRangesMs, beepInsteadOfSilence),
        '-map',
        '0:v?',
        '-map',
        '[aout]',
        '-c:v',
        'copy',
        '-c:a',
        'aac',
        outputPath,
      ];
      final session = await FFmpegKit.executeWithArgumentsAsync(args);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return Result<String?>.success(outputPath);
      }
      final logs = await session.getAllLogsAsString();
      return Result<String?>.err(
        Failure.storage(
          message: 'ffmpeg censor failed (code $returnCode)',
          cause: logs == null || logs.isEmpty ? null : logs,
        ),
      );
    } on Object catch (e) {
      return Result<String?>.err(
        Failure.storage(message: 'ffmpeg censor failed', cause: e),
      );
    }
  }

  /// Builds the `-filter_complex` graph: `volume=enable='between(t,a,b)':
  /// volume=0` mutes every range; when [beepInsteadOfSilence] is set, a
  /// 1 kHz sine (`aevalsrc`) is delayed into each range and mixed back.
  static String _filterGraph(
    List<(int, int)> rangesMs,
    bool beepInsteadOfSilence,
  ) {
    final mutes = <String>[];
    for (final (startMs, endMs) in rangesMs) {
      final a = (startMs / 1000).toStringAsFixed(3);
      final b = (endMs / 1000).toStringAsFixed(3);
      mutes.add("volume=enable='between(t,$a,$b)':volume=0");
    }
    final muteChain = '[0:a]${mutes.join(',')}[muted]';

    if (!beepInsteadOfSilence) {
      return '$muteChain[aout]';
    }

    // One mono 1 kHz sine per range, delayed to its start, mixed over the
    // muted track. `amix` with normalize=0 keeps the (zeroed) music level.
    final beepLabels = <String>[];
    final parts = <String>[muteChain];
    for (var i = 0; i < rangesMs.length; i++) {
      final (startMs, endMs) = rangesMs[i];
      final durationS = ((endMs - startMs) / 1000).toStringAsFixed(3);
      parts.add(
        "aevalsrc='0.35*sin(2*PI*1000*t)':d=$durationS:s=44100[b$i];"
        '[b$i]adelay=${startMs}:all=1[bd$i]',
      );
      beepLabels.add('[bd$i]');
    }
    final inputs = <String>['[muted]', ...beepLabels].join('');
    parts.add('${inputs}amix=inputs=${beepLabels.length + 1}:'
        'normalize=0:dropout_transition=0[aout]');
    return parts.join(';');
  }
}

/// dart:io-backed existence probe (kept out of web builds by the
/// conditional export in `censor_executor.dart`).
Future<bool> localFileExists(String path) async {
  try {
    return await File(path).exists();
  } on Object {
    return false;
  }
}
