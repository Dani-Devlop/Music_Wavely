import 'package:wavely/data/local/db/daos/lyrics_dao.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';

/// Drift-backed [LyricsCache] port over the `lyrics_cache` table.
///
/// Composition-root binding for the lyrics chain (embedded provider, LRCLIB
/// provider, lyrics repository). A `get` without an explicit [provider]
/// defers to [LyricsDao.get]'s "best row" rule (synced LRC preferred, then
/// most recently fetched); `upsert`/`updateOffset` are straight delegates.
class DriftLyricsCache implements LyricsCache {
  /// Creates the cache port over [dao].
  const DriftLyricsCache(this._dao);

  final LyricsDao _dao;

  @override
  Future<CachedLyrics?> get({required int trackId, String? provider}) async {
    final row = await _dao.get(trackId: trackId, provider: provider);
    if (row == null) {
      return null;
    }
    return CachedLyrics(
      trackId: row.trackId,
      provider: row.provider,
      syncedLrc: row.syncedLrc,
      plainText: row.plainText,
      offsetMs: row.offsetMs,
      fetchedAt: row.fetchedAt,
    );
  }

  @override
  Future<void> upsert({
    required int trackId,
    required String provider,
    String? syncedLrc,
    String? plainText,
  }) =>
      _dao.upsert(
        trackId: trackId,
        provider: provider,
        syncedLrc: syncedLrc,
        plainText: plainText,
      );

  @override
  Future<void> updateOffset({
    required int trackId,
    required int offsetMs,
  }) =>
      _dao.updateOffset(trackId: trackId, offsetMs: offsetMs);
}
