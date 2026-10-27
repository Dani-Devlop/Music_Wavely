import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Converts between generated [TracksRow] rows and domain [Track] entities so
/// that DAOs can return entities and the scanner can hand entities back.
abstract final class TrackMapper {
  /// Maps a generated row to its domain representation.
  static Track toDomain(TracksRow row) => Track(
        id: row.id,
        sourceId: row.sourceId,
        sourceTrackId: row.sourceTrackId,
        title: row.title,
        artist: row.artist,
        album: row.album,
        genre: row.genre,
        language: row.language,
        durationMs: row.durationMs,
        bitrate: row.bitrate,
        format: row.format,
        filePath: row.filePath,
        coverPath: row.coverPath,
        explicit: row.explicit,
        addedAt: row.addedAt,
        updatedAt: row.updatedAt,
        playCount: row.playCount,
        lastPlayedAt: row.lastPlayedAt,
      );

  /// Maps [rows] to domain entities (unmodifiable result list).
  static List<Track> toDomainList(Iterable<TracksRow> rows) =>
      rows.map(toDomain).toList(growable: false);

  /// Builds an insert/update companion from a domain [Track].
  ///
  /// Nullable entity fields are wrapped in explicit [Value]s so that `null`
  /// actually clears the column instead of leaving it untouched.
  static TracksCompanion toCompanion(Track track) => TracksCompanion.insert(
        sourceId: track.sourceId,
        sourceTrackId: track.sourceTrackId,
        title: track.title,
        artist: track.artist,
        album: Value(track.album),
        genre: Value(track.genre),
        language: Value(track.language),
        durationMs: track.durationMs,
        bitrate: Value(track.bitrate),
        format: track.format,
        filePath: Value(track.filePath),
        coverPath: Value(track.coverPath),
        explicit: Value(track.explicit),
        addedAt: track.addedAt,
        updatedAt: track.updatedAt,
        playCount: Value(track.playCount),
        lastPlayedAt: Value(track.lastPlayedAt),
      );
}
