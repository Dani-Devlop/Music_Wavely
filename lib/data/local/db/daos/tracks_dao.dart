import 'package:drift/drift.dart';

import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/domain/entities/entities.dart';

part 'tracks_dao.g.dart';

/// Data access for [Tracks] plus the derived artists/albums/genres views and
/// the album/artist projection maintenance used by the library scanner.
@DriftAccessor(tables: [Tracks, Albums, Artists])
class TracksDao extends DatabaseAccessor<AppDatabase> with _$TracksDaoMixin {
  TracksDao(super.attachedDatabase);

  /// Default ordering for [getAll] (trusted internal literal, never user
  /// input — it is interpolated into the ORDER BY clause as-is).
  static const String defaultOrderBy = 'title COLLATE NOCASE ASC';

  /// Fetches [limit] tracks ordered by [orderBy], skipping [offset] rows.
  Future<List<Track>> getAll({
    required int limit,
    required int offset,
    String orderBy = defaultOrderBy,
  }) async {
    final rows = await customSelect(
      'SELECT id FROM tracks ORDER BY $orderBy LIMIT ? OFFSET ?',
      variables: [Variable.withInt(limit), Variable.withInt(offset)],
    ).get();
    return _tracksInIdOrder(
      [for (final row in rows) row.read<int>('id')],
    );
  }

  /// Inserts a track and returns its row id.
  Future<int> insertTrack(TracksCompanion entry) =>
      into(tracks).insert(entry);

  /// Inserts the track, or — when a row with the same
  /// `sourceId`+`sourceTrackId` already exists — updates it in place.
  ///
  /// The update path preserves `id`, `playCount`, `lastPlayedAt` and
  /// `addedAt`, refreshes `updatedAt` (unless the entry carries one) and
  /// returns the resulting domain entity.
  Future<Track> upsertBySource(TracksCompanion entry) async {
    final sourceId = entry.sourceId.value;
    final sourceTrackId = entry.sourceTrackId.value;
    final existing = await (select(tracks)
          ..where(
            (t) =>
                t.sourceId.equals(sourceId) &
                t.sourceTrackId.equals(sourceTrackId),
          ))
        .getSingleOrNull();
    if (existing == null) {
      final id = await into(tracks).insert(entry);
      final row =
          await (select(tracks)..where((t) => t.id.equals(id))).getSingle();
      return TrackMapper.toDomain(row);
    }
    await (update(tracks)..where((t) => t.id.equals(existing.id))).write(
      TracksCompanion(
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        genre: entry.genre,
        language: entry.language,
        durationMs: entry.durationMs,
        bitrate: entry.bitrate,
        format: entry.format,
        filePath: entry.filePath,
        coverPath: entry.coverPath,
        explicit: entry.explicit,
        updatedAt: entry.updatedAt.present
            ? entry.updatedAt
            : Value(DateTime.now()),
      ),
    );
    final row = await (select(tracks)
          ..where((t) => t.id.equals(existing.id)))
        .getSingle();
    return TrackMapper.toDomain(row);
  }

  /// Loads a single track by primary key.
  Future<Track?> getById(int id) async {
    final row = await (select(tracks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : TrackMapper.toDomain(row);
  }

  /// Loads the tracks with the given ids (result order follows the database,
  /// not [ids]).
  Future<List<Track>> byIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const <Track>[];
    }
    final rows = await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    return TrackMapper.toDomainList(rows);
  }

  /// All tracks of [artist], grouped by album then title (both case-folded).
  Future<List<Track>> byArtist(String artist) async {
    final rows = await (select(tracks)
          ..where((t) => t.artist.collate(Collate.noCase).equals(artist)))
        .get();
    final result = TrackMapper.toDomainList(rows).toList();
    result.sort(_albumThenTitle);
    return result;
  }

  /// All tracks of one album ([artist] + [album], both case-folded), ordered
  /// by title.
  Future<List<Track>> byAlbum({
    required String artist,
    required String album,
  }) async {
    final rows = await (select(tracks)
          ..where(
            (t) =>
                t.artist.collate(Collate.noCase).equals(artist) &
                t.album.collate(Collate.noCase).equals(album),
          ))
        .get();
    final result = TrackMapper.toDomainList(rows).toList();
    result.sort(_albumThenTitle);
    return result;
  }

  /// All tracks tagged with [genre], ordered by title.
  Future<List<Track>> byGenre(String genre) async {
    final rows = await (select(tracks)
          ..where((t) => t.genre.collate(Collate.noCase).equals(genre)))
        .get();
    final result = TrackMapper.toDomainList(rows).toList();
    result.sort(_albumThenTitle);
    return result;
  }

  /// Full-text search over title/artist/album via the `tracks_fts` FTS5
  /// table, ordered by relevance (`rank`) and capped at
  /// [AppConstants.ftsPageSize] results.
  ///
  /// Blank queries short-circuit to an empty list. Tokens are matched as an
  /// implicit AND, and only the LAST token becomes a prefix query, so
  /// `paper boa` finds "Paper Boats" while the user is still typing.
  Future<List<Track>> searchFts(String query) async {
    final match = ftsPrefixQuery(query);
    if (match == null) {
      return const <Track>[];
    }
    final rows = await customSelect(
      'SELECT t.id AS track_id FROM tracks t '
      'JOIN tracks_fts f ON t.id = f.rowid '
      'WHERE f MATCH ? '
      'ORDER BY f.rank '
      'LIMIT ?',
      variables: [
        Variable.withString(match),
        Variable.withInt(AppConstants.ftsPageSize),
      ],
    ).get();
    return _tracksInIdOrder(
      [for (final row in rows) row.read<int>('track_id')],
    );
  }

  /// Number of tracks for one source (e.g. `local`).
  Future<int> countBySource(String sourceId) async {
    final count = tracks.id.count();
    final query = selectOnly(tracks)
      ..addColumns([count])
      ..where(tracks.sourceId.equals(sourceId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Total number of tracks in the library.
  Future<int> countAll() async {
    final count = tracks.id.count();
    final query = selectOnly(tracks)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Distinct artists with track and album counts, alphabetically (A→Z,
  /// case-folded). Cover paths are null because covers are per-track data.
  Future<List<Artist>> distinctArtists() async {
    final rows = await customSelect(
      'SELECT artist AS artist_name, COUNT(*) AS track_count, '
      'COUNT(DISTINCT album) AS album_count '
      'FROM tracks '
      'GROUP BY artist COLLATE NOCASE '
      'ORDER BY artist COLLATE NOCASE ASC',
    ).get();
    return <Artist>[
      for (final row in rows)
        Artist(
          name: row.read<String>('artist_name'),
          trackCount: row.read<int>('track_count'),
          albumCount: row.read<int>('album_count'),
        ),
    ];
  }

  /// Distinct albums (title × artist, case-folded) with counts, newest
  /// first. Tracks without album metadata collapse under `Unknown Album`.
  /// Year is not stored on tracks, so [Album.year] stays null here.
  Future<List<Album>> distinctAlbums() async {
    final rows = await customSelect(
      "SELECT COALESCE(album, '$_unknownAlbum') AS album_title, "
      "COALESCE(artist, '$_unknownArtist') AS album_artist, "
      'COUNT(*) AS track_count, '
      'MIN(added_at) AS first_added '
      'FROM tracks '
      'GROUP BY COALESCE(album, \'$_unknownAlbum\'), '
      "COALESCE(artist, '$_unknownArtist') "
      'ORDER BY first_added DESC',
    ).get();
    return <Album>[
      for (final row in rows)
        Album(
          key: _albumKey(
            artist: row.read<String>('album_artist'),
            title: row.read<String>('album_title'),
          ),
          title: row.read<String>('album_title'),
          artist: row.read<String>('album_artist'),
          trackCount: row.read<int>('track_count'),
          addedAt: row.read<DateTime>('first_added'),
        ),
    ];
  }

  /// Distinct genre tags, alphabetically (case-folded).
  Future<List<String>> distinctGenres() async {
    final rows = await customSelect(
      'SELECT genre FROM tracks '
      'WHERE genre IS NOT NULL '
      'GROUP BY genre COLLATE NOCASE '
      'ORDER BY genre COLLATE NOCASE ASC',
    ).get();
    return <String>[for (final row in rows) row.read<String>('genre')];
  }

  /// Recomputes one album projection row from the `tracks` table.
  ///
  /// Called by the scanner post-pass for every album it touched; an existing
  /// row keeps its `addedAt`/`year`, only the count (and a newly available
  /// cover) are refreshed.
  Future<void> upsertAlbumProjection({
    required String title,
    required String artist,
    String? coverPath,
  }) async {
    final key = _albumKey(artist: artist, title: title);
    final count = tracks.id.count();
    final countQuery = selectOnly(tracks)
      ..addColumns([count])
      ..where(
        tracks.album.collate(Collate.noCase).equals(title) &
            tracks.artist.collate(Collate.noCase).equals(artist),
      );
    final countRow = await countQuery.getSingle();
    final trackCount = countRow.read(count) ?? 0;
    final existing =
        await (select(albums)..where((a) => a.key.equals(key)))
            .getSingleOrNull();
    if (existing == null) {
      await into(albums).insert(
        AlbumsCompanion.insert(
          key: key,
          title: title,
          artist: artist,
          coverPath: Value(coverPath),
          addedAt: DateTime.now(),
          trackCount: Value(trackCount),
        ),
      );
      return;
    }
    await (update(albums)..where((a) => a.key.equals(key))).write(
      AlbumsCompanion(
        title: Value(title),
        artist: Value(artist),
        coverPath:
            coverPath == null ? const Value.absent() : Value(coverPath),
        trackCount: Value(trackCount),
      ),
    );
  }

  /// Recomputes one artist projection row (track + album counts) from the
  /// `tracks` table; name matching is case-folded.
  Future<void> upsertArtistProjection({
    required String name,
    String? coverPath,
  }) async {
    final counts = await customSelect(
      'SELECT COUNT(*) AS track_count, '
      'COUNT(DISTINCT album) AS album_count '
      'FROM tracks '
      'WHERE artist = ? COLLATE NOCASE',
      variables: [Variable.withString(name)],
    ).getSingle();
    final existing = await customSelect(
      'SELECT id FROM artists WHERE name = ? COLLATE NOCASE LIMIT 1',
      variables: [Variable.withString(name)],
    ).getSingleOrNull();
    if (existing == null) {
      await into(artists).insert(
        ArtistsCompanion.insert(
          name: name,
          coverPath: Value(coverPath),
          trackCount: Value(counts.read<int>('track_count')),
          albumCount: Value(counts.read<int>('album_count')),
        ),
      );
      return;
    }
    await (update(artists)
          ..where((a) => a.id.equals(existing.read<int>('id'))))
        .write(
      ArtistsCompanion(
        trackCount: Value(counts.read<int>('track_count')),
        albumCount: Value(counts.read<int>('album_count')),
        coverPath:
            coverPath == null ? const Value.absent() : Value(coverPath),
      ),
    );
  }

  /// Builds the FTS5 MATCH expression for a free-form [query].
  ///
  /// Every whitespace-separated token is wrapped in double quotes (internal
  /// quotes escaped by doubling) and joined with spaces — FTS5 reads that as
  /// an implicit AND. Only the LAST token gets the `*` prefix suffix, so
  /// `paper boa` becomes `"paper" "boa"*`: completed words must match fully
  /// while the word currently being typed may be a prefix. Returns null for
  /// blank queries so callers can skip the search entirely.
  static String? ftsPrefixQuery(String query) {
    final tokens = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) {
        buffer.write(' ');
      }
      buffer.write('"${tokens[i].replaceAll('"', '""')}"');
      if (i == tokens.length - 1) {
        buffer.write('*');
      }
    }
    return buffer.toString();
  }

  static const String _unknownAlbum = 'Unknown Album';
  static const String _unknownArtist = 'Unknown Artist';

  static String _albumKey({required String artist, required String title}) =>
      '${artist.toLowerCase()}::${title.toLowerCase()}';

  static int _albumThenTitle(Track a, Track b) {
    final byAlbum =
        (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase());
    if (byAlbum != 0) {
      return byAlbum;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  /// Re-fetches rows for [ids] and returns them in the order of [ids] (used
  /// after `customSelect` joins so that generated row mapping — with proper
  /// bool/DateTime decoding — still applies).
  Future<List<Track>> _tracksInIdOrder(List<int> ids) async {
    if (ids.isEmpty) {
      return const <Track>[];
    }
    final rows = await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = <int, TracksRow>{
      for (final row in rows) row.id: row,
    };
    return <Track>[
      for (final id in ids)
        if (byId[id] case final row?) TrackMapper.toDomain(row),
    ];
  }
}
