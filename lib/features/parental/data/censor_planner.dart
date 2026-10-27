import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

/// A merged, monotonically ordered mute window in milliseconds.
typedef CensorRange = (int startMs, int endMs);

/// Result of [CensorPlanner.plan]: the mute windows to render, whether a
/// usable plan exists at all, and the reason when it does not.
class CensorPlan {
  const CensorPlan({
    this.ranges = const <CensorRange>[],
    required this.hasPlan,
    this.reason,
  });

  /// Sorted, non-overlapping mute windows (adjacent windows are merged).
  final List<CensorRange> ranges;

  /// True when the lyrics carried usable sync data (even when [ranges] ends
  /// up empty because nothing matched — e.g. whitelist-only text).
  final bool hasPlan;

  /// Why no plan could be built (`no synced lyrics`), null otherwise.
  final String? reason;

  /// Convenience for executors/UI: is there actually anything to mute?
  bool get isEmpty => ranges.isEmpty;
}

/// Builds the mute-window plan for one track from its synced lyrics.
///
/// Line-level policy: when a lyric line contains any blocked-word match, the
/// whole line is muted from [lineStartTimeMs] until the start of the next
/// line, or — for the last line / when the next stamp is missing — until
/// [lineTailMs] after the line start.
class CensorPlanner {
  CensorPlanner._();

  /// Tail applied when a matched line has no following line to bound it.
  static const int lineTailMs = 4000;

  /// Plans the censor ranges for [lyrics] using [matcher].
  static CensorPlan plan({
    required LyricsResult? lyrics,
    required WordMatcher matcher,
  }) {
    if (lyrics == null || !lyrics.synced || lyrics.lines.isEmpty) {
      return const CensorPlan(
        hasPlan: false,
        reason: 'no synced lyrics',
      );
    }

    final lines = lyrics.lines;
    final ranges = <CensorRange>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (matcher.matches(line.text).isEmpty) {
        continue;
      }
      final startMs = line.startTime.inMilliseconds;
      final endMs = i + 1 < lines.length
          ? lines[i + 1].startTime.inMilliseconds
          : startMs + lineTailMs;
      ranges.add((startMs, endMs));
    }

    // Merge overlapping AND adjacent windows so executors see clean spans.
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <CensorRange>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final (start, end) = merged.last;
        merged[merged.length - 1] = (start, end > range.$2 ? end : range.$2);
      } else {
        merged.add(range);
      }
    }

    return CensorPlan(hasPlan: true, ranges: List.unmodifiable(merged));
  }
}
