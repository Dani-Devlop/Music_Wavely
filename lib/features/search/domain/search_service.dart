import 'dart:async';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';

/// One hit of the unified (online) search.
class UnifiedSearchHit {
  /// Creates a hit.
  const UnifiedSearchHit({required this.track, required this.sourceId});

  /// Canonical track returned by the source.
  final Track track;

  /// Id of the source that produced the hit.
  final String sourceId;

  /// Quality label parsed from the format / URL (`flac`, `mp3`, ...).
  String get qualityLabel {
    final String f = track.format.toLowerCase();
    if (f.contains('flac')) {
      return 'FLAC';
    }
    if (f.contains('ogg')) {
      return 'OGG';
    }
    if (f.contains('wav')) {
      return 'WAV';
    }
    return f.isEmpty ? 'AUDIO' : f.toUpperCase();
  }
}

/// Per-source outcome of a unified search round.
class UnifiedSearchResult {
  /// Creates the result.
  const UnifiedSearchResult({
    required this.hits,
    required this.failedSources,
  });

  /// Merged + deduplicated hits across sources.
  final List<UnifiedSearchHit> hits;

  /// Source ids that threw or timed out (surfaced as soft errors).
  final List<String> failedSources;

  /// Empty result.
  static const UnifiedSearchResult empty = UnifiedSearchResult(
    hits: <UnifiedSearchHit>[],
    failedSources: <String>[],
  );
}

/// Queries every enabled online source in parallel and merges + dedupes the
/// responses.
///
/// Contract (Stage 2.1 Section 8):
/// - all sources queried simultaneously with `Future.wait`;
/// - per-source timeout: 5 s (a slow source never stalls the others);
/// - dedupe by ISRC when available, else by
///   `title.toLowerCase() + artist.toLowerCase()` with Levenshtein
///   distance < 3.
class SearchService {
  /// Creates the service over [sources]; [timeout] and [now] injectable for
  /// tests.
  SearchService({
    required List<SourceProvider> sources,
    this.timeout = const Duration(seconds: 5),
    DateTime Function()? now,
  })  : _sources = List<SourceProvider>.of(sources),
        _now = now ?? DateTime.now;

  final List<SourceProvider> _sources;
  final Duration timeout;
  final DateTime Function() _now;

  /// Immutable view of the sources this instance queries.
  List<SourceProvider> get sources => List.unmodifiable(_sources);

  /// Runs the unified search for [query].
  Future<UnifiedSearchResult> search(
    String query, {
    int limitPerSource = 20,
  }) async {
    if (query.trim().isEmpty || _sources.isEmpty) {
      return UnifiedSearchResult.empty;
    }
    final List<UnifiedSearchHit> hits = <UnifiedSearchHit>[];
    final List<String> failed = <String>[];
    await Future.wait(<Future<void>>[
      for (final SourceProvider source in _sources)
        () async {
          try {
            final List<Track> tracks = await source
                .search(query, limit: limitPerSource)
                .timeout(timeout);
            for (final Track t in tracks) {
              hits.add(UnifiedSearchHit(track: t, sourceId: source.id));
            }
          } on TimeoutException {
            failed.add(source.id);
          } on Object {
            failed.add(source.id);
          }
        }(),
    ]);
    return UnifiedSearchResult(
      hits: dedupe(hits),
      failedSources: failed,
    );
  }

  /// Dedupes [hits] preserving first-seen order.
  ///
  /// ISRC takes priority when both hits carry one (no [Track] field ships
  /// ISRC today — the branch is wired for future sources that provide it via
  /// [isrcOf]); otherwise the normalised title+artist key with Levenshtein
  /// distance < 3 decides.
  List<UnifiedSearchHit> dedupe(List<UnifiedSearchHit> hits) {
    final List<UnifiedSearchHit> out = <UnifiedSearchHit>[];
    for (final UnifiedSearchHit hit in hits) {
      final String? isrc = isrcOf(hit.track);
      var duplicate = false;
      for (final UnifiedSearchHit kept in out) {
        final String? keptIsrc = isrcOf(kept.track);
        if (isrc != null && keptIsrc != null) {
          if (isrc == keptIsrc) {
            duplicate = true;
            break;
          }
          continue;
        }
        if (_sameWork(hit.track, kept.track)) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        out.add(hit);
      }
    }
    return out;
  }

  /// Two tracks are the same work when their normalised titles are within
  /// Levenshtein distance 3 and their artists match (or either is blank).
  bool _sameWork(Track a, Track b) {
    final String titleA = a.title.trim().toLowerCase();
    final String titleB = b.title.trim().toLowerCase();
    // Stage 3 audit (BUG-14): distance 3 collapses distinct short titles
    // ("Run" vs "Sun"); short titles therefore require exact equality.
    if (titleA.length < 5 || titleB.length < 5) {
      return titleA == titleB;
    }
    if (levenshtein(titleA, titleB) >= 3) {
      return false;
    }
    final String artistA = a.artist.trim().toLowerCase();
    final String artistB = b.artist.trim().toLowerCase();
    if (artistA.isEmpty || artistB.isEmpty) {
      return true;
    }
    return levenshtein(artistA, artistB) < 3;
  }

  /// ISRC hook — no [Track] field carries an ISRC today; sources that add
  /// one later override this (keeps the dedupe contract testable).
  String? isrcOf(Track t) => null;
}

/// Levenshtein edit distance (iterative, two-row DP).
int levenshtein(String a, String b) {
  if (a == b) {
    return 0;
  }
  if (a.isEmpty) {
    return b.length;
  }
  if (b.isEmpty) {
    return a.length;
  }
  final List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
  final List<int> curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final int cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = _min3(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost);
    }
    prev.setAll(0, curr);
  }
  return prev[b.length];
}

int _min3(int x, int y, int z) => x < y ? (x < z ? x : z) : (y < z ? y : z);
