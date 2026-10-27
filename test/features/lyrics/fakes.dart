/// authored, awaiting local run.
///
/// Shared hand-rolled fakes for the lyrics test suites (parser, LRCLIB
/// provider, repository, sync controller). Deliberately self-contained —
/// `test/support` is owned by another agent.
library;

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';

/// In-memory [LyricsCache] recording every write so suites can assert what
/// the repository/providers persisted, and optionally throwing to exercise
/// the "cache failures must not break lyric delivery" contract.
class FakeLyricsCache implements LyricsCache {
  /// Rows keyed by track id (one row per track, like the real table).
  final Map<int, CachedLyrics> rows = <int, CachedLyrics>{};

  /// Recorded [upsert] calls in order.
  final List<({
    int trackId,
    String provider,
    String? syncedLrc,
    String? plainText,
  })>
  upserts = <({int trackId, String provider, String? syncedLrc,
      String? plainText})>[];

  /// Recorded [updateOffset] calls in order.
  final List<({int trackId, int offsetMs})> offsetUpdates =
      <({int trackId, int offsetMs})>[];

  /// When non-null, [get] throws this (simulates a broken store).
  Object? getError;

  /// When non-null, [upsert] throws this.
  Object? upsertError;

  int getCallCount = 0;

  void seed(CachedLyrics row) => rows[row.trackId] = row;

  CachedLyrics? rowFor(int trackId) => rows[trackId];

  @override
  Future<CachedLyrics?> get({required int trackId, String? provider}) async {
    getCallCount++;
    if (getError != null) {
      throw getError!;
    }
    final CachedLyrics? row = rows[trackId];
    if (row == null) {
      return null;
    }
    if (provider != null && row.provider != provider) {
      return null;
    }
    return row;
  }

  @override
  Future<void> upsert({
    required int trackId,
    required String provider,
    String? syncedLrc,
    String? plainText,
  }) async {
    if (upsertError != null) {
      throw upsertError!;
    }
    upserts.add((
      trackId: trackId,
      provider: provider,
      syncedLrc: syncedLrc,
      plainText: plainText,
    ));
    final int previousOffset = rows[trackId]?.offsetMs ?? 0;
    rows[trackId] = CachedLyrics(
      trackId: trackId,
      provider: provider,
      syncedLrc: syncedLrc,
      plainText: plainText,
      offsetMs: previousOffset,
      fetchedAt: DateTime(2024, 1, 1),
    );
  }

  @override
  Future<void> updateOffset({
    required int trackId,
    required int offsetMs,
  }) async {
    offsetUpdates.add((trackId: trackId, offsetMs: offsetMs));
    final CachedLyrics? row = rows[trackId];
    if (row != null) {
      rows[trackId] = CachedLyrics(
        trackId: row.trackId,
        provider: row.provider,
        syncedLrc: row.syncedLrc,
        plainText: row.plainText,
        offsetMs: offsetMs,
        fetchedAt: row.fetchedAt,
      );
    }
  }
}

/// A [LyricsProvider] with a scripted answer: returns [result] (a miss when
/// null) or throws [error], counting every call. Used to probe the chain
/// order and the failure-degradation contract of the lyrics repository.
class ScriptedLyricsProvider implements LyricsProvider {
  ScriptedLyricsProvider(
    this.id, {
    this.result,
    this.error,
  });

  @override
  final String id;

  final LyricsResult? result;

  final Object? error;

  int calls = 0;

  Track? lastTrack;

  @override
  Future<LyricsResult?> fetch(Track t) async {
    calls++;
    lastTrack = t;
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

/// Builds a canonical local [Track] with sane defaults for lyrics tests.
Track makeTrack({
  int? id,
  String title = 'Song',
  String artist = 'Artist',
  String? album,
  int durationMs = 180000,
  String? filePath,
  String? coverPath,
}) {
  return Track(
    id: id,
    sourceId: Track.localSourceId,
    sourceTrackId: 'src-${id ?? title}',
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    format: 'mp3',
    filePath: filePath,
    coverPath: coverPath,
    addedAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}
