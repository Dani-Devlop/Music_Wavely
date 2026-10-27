import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';

part 'lyrics_dao.g.dart';

/// Data access for [LyricsCache] — raw LRC / plain-text lyrics per track and
/// provider, written by the scanner (embedded tags) and the lyrics providers.
@DriftAccessor(tables: [LyricsCache])
class LyricsDao extends DatabaseAccessor<AppDatabase>
    with _$LyricsDaoMixin {
  LyricsDao(super.attachedDatabase);

  /// Provider tag for lyrics extracted from the audio file's own tags
  /// (USLT/SYLT/LYRICS blocks) during the library scan.
  static const String embeddedProvider = 'embedded';

  /// Loads the cached lyrics of a track.
  ///
  /// With an explicit [provider] exactly that row is returned. When
  /// [provider] is null the "best" row wins: rows WITH synced LRC are
  /// preferred over plain text, then the most recently fetched one.
  Future<LyricsCacheRow?> get({required int trackId, String? provider}) {
    final query = select(lyricsCache)
      ..where((r) => r.trackId.equals(trackId));
    if (provider != null) {
      query.where((r) => r.provider.equals(provider));
    } else {
      query
        ..orderBy([
          // `false` (i.e. NOT NULL syncedLrc) sorts first.
          (r) => OrderingTerm.asc(r.syncedLrc.isNull()),
          (r) => OrderingTerm.desc(r.fetchedAt),
        ])
        ..limit(1);
    }
    return query.getSingleOrNull();
  }

  /// Inserts or updates the lyrics of one (track, provider) pair.
  ///
  /// Fields not supplied are preserved (`COALESCE(excluded.x, x)`); the row
  /// is stamped with a fresh `fetchedAt` and the offset resets to 0 because
  /// new lyrics text invalidates the old manual offset.
  Future<void> upsert({
    required int trackId,
    required String provider,
    String? syncedLrc,
    String? plainText,
  }) {
    return customStatement(
      'INSERT INTO lyrics_cache '
      '(track_id, provider, synced_lrc, plain_text, offset_ms, fetched_at) '
      'VALUES (?, ?, ?, ?, 0, ?) '
      'ON CONFLICT (track_id, provider) DO UPDATE SET '
      'synced_lrc = COALESCE(excluded.synced_lrc, lyrics_cache.synced_lrc), '
      'plain_text = COALESCE(excluded.plain_text, lyrics_cache.plain_text), '
      'offset_ms = 0, '
      'fetched_at = excluded.fetched_at',
      [
        Variable.withInt(trackId),
        Variable.withString(provider),
        Variable<String>(syncedLrc),
        Variable<String>(plainText),
        Variable.withDateTime(DateTime.now()),
      ],
    );
  }

  /// Applies a manual sync [offsetMs] to every cached lyrics row of the
  /// track (all providers share one user offset per track).
  Future<void> updateOffset({required int trackId, required int offsetMs}) {
    return (update(lyricsCache)..where((r) => r.trackId.equals(trackId)))
        .write(LyricsCacheCompanion(offsetMs: Value(offsetMs)));
  }
}
