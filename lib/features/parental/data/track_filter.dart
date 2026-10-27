import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

/// What the parental filter decided about one track.
enum TrackVerdict {
  /// Play as-is.
  allowed,

  /// Never load — the QueueManager should auto-skip to the next track.
  blocked,

  /// Load the censored render (or fall back to the original when rendering
  /// fails).
  censorNeeded,
}

/// Static + lyrics-based parental gate for a single track.
///
/// Order of rules (first hit wins):
/// 1. artist / album / genre on a blocklist (case-insensitive) → blocked;
/// 2. no lyrics at all and the no-lyrics policy is on → blocked;
/// 3. any lyric-line match → censorNeeded;
/// 4. otherwise → allowed.
class TrackFilter {
  TrackFilter({
    required this.words,
    required this.blockNoLyrics,
    this.blockedArtists = const [],
    this.blockedAlbums = const [],
    this.blockedGenres = const [],
  });

  /// Blocked words (stored rows; [evaluate] matches through [matcher]).
  final List<BlockedWordRow> words;

  /// Block tracks that have no lyrics source at all.
  final bool blockNoLyrics;

  /// Blocklists matched case-insensitively against whole metadata values.
  final List<String> blockedArtists;
  final List<String> blockedAlbums;
  final List<String> blockedGenres;

  /// True when any blocked word is configured (UI convenience).
  bool get hasWords => words.isNotEmpty;

  /// Classifies [track] given its [lyrics] (null = no lyrics found) and a
  /// [matcher] built from the current blocked-word list.
  Future<TrackVerdict> evaluate({
    required Track track,
    required LyricsResult? lyrics,
    required WordMatcher matcher,
  }) async {
    if (_matchesAny(track.artist, blockedArtists) ||
        _matchesAny(track.album, blockedAlbums) ||
        _matchesAny(track.genre, blockedGenres)) {
      return TrackVerdict.blocked;
    }

    final noLyrics = lyrics == null || lyrics.lines.isEmpty;
    if (noLyrics && blockNoLyrics) {
      return TrackVerdict.blocked;
    }

    if (lyrics != null) {
      for (final line in lyrics.lines) {
        if (matcher.matches(line.text).isNotEmpty) {
          return TrackVerdict.censorNeeded;
        }
      }
    }

    return TrackVerdict.allowed;
  }

  /// Case-insensitive whole-value comparison (trimmed on both sides).
  static bool _matchesAny(String? value, List<String> blocklist) {
    if (value == null || value.isEmpty) {
      return false;
    }
    final needle = value.trim().toLowerCase();
    return blocklist.any(
      (blocked) => blocked.trim().toLowerCase() == needle,
    );
  }
}
