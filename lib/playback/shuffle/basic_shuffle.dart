import 'dart:math';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Deterministic Fisher-Yates shuffle for the play queue.
///
/// Rules (Stage 1.1):
/// - Same seed + same input -> same output (unit-tested determinism).
/// - When [currentIndex] is given, the currently playing track becomes the
///   first element of the result (playback continues from the front).
/// - Tracks whose ids appear in [recentlyPlayedIds] are pushed out of the
///   first [AppConstants.shuffleNoRepeatWindow] positions via a best-effort
///   swap with candidates from the tail; if no fresh candidate exists
///   (queue too small / everything recently played) they stay where the
///   shuffle put them — exclusion is never allowed to break the
///   current-track-first rule at position 0.
class BasicShuffle {
  const BasicShuffle();

  List<Track> shuffle(
    List<Track> tracks, {
    required int? currentIndex,
    required int seed,
    List<int> recentlyPlayedIds = const <int>[],
  }) {
    final result = List<Track>.of(tracks);
    if (result.length <= 1) {
      return result;
    }
    final rng = Random(seed);
    for (var i = result.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = result[i];
      result[i] = result[j];
      result[j] = tmp;
    }
    final hasCurrent =
        currentIndex != null && currentIndex >= 0 && currentIndex < tracks.length;
    if (hasCurrent) {
      final anchor = tracks[currentIndex];
      final at = result.indexOf(anchor);
      if (at > 0) {
        final tmp = result[0];
        result[0] = result[at];
        result[at] = tmp;
      }
    }
    _applyNoRepeatWindow(
      result,
      recentIds: recentlyPlayedIds.toSet(),
      keepFirst: hasCurrent ? 1 : 0,
    );
    return result;
  }

  void _applyNoRepeatWindow(
    List<Track> result, {
    required Set<int> recentIds,
    required int keepFirst,
  }) {
    if (recentIds.isEmpty) {
      return;
    }
    final windowEnd =
        min(AppConstants.shuffleNoRepeatWindow, result.length);
    for (var i = keepFirst; i < windowEnd; i++) {
      final id = result[i].id;
      if (id == null || !recentIds.contains(id)) {
        continue;
      }
      // Best effort: swap with the freshest tail candidate available.
      for (var j = result.length - 1; j >= windowEnd; j--) {
        final candidateId = result[j].id;
        if (candidateId == null || !recentIds.contains(candidateId)) {
          final tmp = result[i];
          result[i] = result[j];
          result[j] = tmp;
          break;
        }
      }
    }
  }
}
