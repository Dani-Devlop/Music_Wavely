import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Port abstracting the persisted lyrics cache (`lyrics_cache` table).
///
/// The Drift-backed implementation lives in the data layer and is wired in
/// the composition root (Task 4). Feature code (embedded provider, LRCLIB
/// provider, lyrics repository) depends ONLY on this interface.
abstract class LyricsCache {
  /// Returns the cached lyrics for [trackId] (any provider) —
  /// [provider] optionally restricts to one provider row.
  Future<CachedLyrics?> get({required int trackId, String? provider});

  /// Inserts or updates the cache row (LRCLIB results are cached forever,
  /// per Stage 1.1; embedded lyrics are written once during library scan).
  Future<void> upsert({
    required int trackId,
    required String provider,
    String? syncedLrc,
    String? plainText,
  });

  /// Persists a user-adjusted lyric offset in milliseconds.
  Future<void> updateOffset({required int trackId, required int offsetMs});
}

/// Immutable snapshot of a cached lyrics row.
class CachedLyrics {
  const CachedLyrics({
    required this.trackId,
    required this.provider,
    required this.offsetMs,
    required this.fetchedAt,
    this.syncedLrc,
    this.plainText,
  });

  final int trackId;
  final String provider;
  final String? syncedLrc;
  final String? plainText;
  final int offsetMs;
  final DateTime fetchedAt;

  bool get hasSynced => syncedLrc != null && syncedLrc!.trim().isNotEmpty;

  /// Returns null: raw cached rows are parsed by `LrcParser` in the lyrics
  /// data/domain layer (see `LyricsRepository._parseRow` and
  /// `EmbeddedLyricsProvider.fetch`), not by this snapshot class.
  LyricsResult? toResult() => null;
}

/// Fallback no-op cache used before the composition root overrides
/// [lyricsCacheProvider] with the Drift-backed implementation.
class NullLyricsCache implements LyricsCache {
  const NullLyricsCache();

  @override
  Future<CachedLyrics?> get({required int trackId, String? provider}) async =>
      null;

  @override
  Future<void> upsert({
    required int trackId,
    required String provider,
    String? syncedLrc,
    String? plainText,
  }) async {}

  @override
  Future<void> updateOffset({
    required int trackId,
    required int offsetMs,
  }) async {}
}

/// Composition root MUST override this provider (Task 4 wiring).
final lyricsCacheProvider = Provider<LyricsCache>(
  (ref) => const NullLyricsCache(),
);
