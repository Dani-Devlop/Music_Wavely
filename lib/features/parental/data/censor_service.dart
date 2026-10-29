import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/censor_executor.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';

/// Provides the directory used for censored renders; returns null when no
/// cache directory is available (web, permission denied, …).
typedef CacheDirProvider = Future<String?> Function();

/// The audio-render seam implemented by [FfmpegCensorExecutor] (io arm) and
/// by fakes in tests.
///
/// Implementations must never THROW — every failure is returned inside the
/// [Result] so the queue layer can fall back to the original file; a broken
/// censor pipeline must never brick playback.
abstract class AudioCensorExecutor {
  const AudioCensorExecutor();

  /// Renders [muteRangesMs] of [inputPath] into [outputPath], optionally
  /// layering a 1 kHz beep instead of pure silence.
  Future<Result<String?>> render({
    required String inputPath,
    required String outputPath,
    required List<(int, int)> muteRangesMs,
    required bool beepInsteadOfSilence,
  });
}

/// Renders a censored copy of a local track according to a [CensorPlan].
///
/// Flow: resolve cache dir → short-circuit on an existing cached render →
/// validate the local input file → hand the mute ranges to the
/// [AudioCensorExecutor] → propagate its [Result]. On failure the caller
/// (QueueManager) falls back to the ORIGINAL file, so censoring must never
/// block playback.
///
/// Threading: no [Isolate] is used — FFmpegKit executes on its own native
/// thread and reports back through futures, so an isolate would only add
/// copy overhead (documented v1 decision).
class CensorService {
  CensorService({
    required this.executor,
    required this.cacheDirProvider,
    this.beepInsteadOfSilence = true,
  });

  /// The ffmpeg (or fake/test) renderer.
  final AudioCensorExecutor executor;

  /// Where censored renders are cached.
  final CacheDirProvider cacheDirProvider;

  /// v1 policy: matched spans get a 1 kHz beep instead of pure silence
  /// (severity-aware mute-vs-beep is a later pass).
  final bool beepInsteadOfSilence;

  /// Renders (or returns the cached) censored file for [track].
  ///
  /// Returns `Success(null)` when nothing needs censoring (empty plan) and
  /// `Err` when the track has no local file or the render fails.
  Future<Result<String?>> censorTrack({
    required Track track,
    required CensorPlan plan,
  }) async {
    if (!plan.hasPlan || plan.ranges.isEmpty) {
      return const Result<String?>.success(null);
    }

    final cacheDir = await cacheDirProvider();
    if (cacheDir == null || cacheDir.isEmpty) {
      return const Result<String?>.err(
        Failure.storage(message: 'no cache directory'),
      );
    }

    // Cache key is the track only (contract: `track-<id>.censored.m4a`);
    // renders are refreshed by the settings' clear-cache flow rather than
    // plan-hash-named files.
    final output = '$cacheDir/${_trackKey(track)}.censored.m4a';
    if (await localFileExists(output)) {
      return Result<String?>.success(output);
    }

    final inputPath = track.filePath;
    if (inputPath == null || inputPath.isEmpty) {
      return const Result<String?>.err(
        Failure.storage(message: 'no local file'),
      );
    }
    if (!await localFileExists(inputPath)) {
      return const Result<String?>.err(
        Failure.storage(message: 'no local file'),
      );
    }

    return executor.render(
      inputPath: inputPath,
      outputPath: output,
      muteRangesMs: plan.ranges,
      beepInsteadOfSilence: beepInsteadOfSilence,
    );
  }

  /// Stable cache-file key: db id when present, else a sanitized source id.
  static String _trackKey(Track track) {
    final id = track.id;
    if (id != null) {
      return 'track-$id';
    }
    final sanitized = track.sourceTrackId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return 'track-$sanitized';
  }
}
