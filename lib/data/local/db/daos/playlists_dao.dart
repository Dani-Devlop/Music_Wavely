import 'package:drift/drift.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/mappers/track_mapper.dart';
import 'package:wavely/data/local/db/tables/playlist_items.dart';
import 'package:wavely/data/local/db/tables/playlists.dart';
import 'package:wavely/data/local/db/tables/tracks.dart';
import 'package:wavely/domain/entities/entities.dart';

part 'playlists_dao.g.dart';

/// Data access for user-curated playlists (Playlists tab + multi-select
/// "Add to Playlist").
@DriftAccessor(tables: [Playlists, PlaylistItems, Tracks])
class PlaylistsDao extends DatabaseAccessor<AppDatabase>
    with _$PlaylistsDaoMixin {
  PlaylistsDao(super.attachedDatabase);

  /// All playlists with their item counts, name-ordered (case-folded).
  Future<List<Playlist>> getAll() async {
    final rows = await customSelect(
      'SELECT p.id, p.name, p.description, p.cover_path, p.created_at, '
      'p.updated_at, COUNT(pi.id) AS item_count '
      'FROM playlists p '
      'LEFT JOIN playlist_items pi ON pi.playlist_id = p.id '
      'GROUP BY p.id '
      'ORDER BY p.name COLLATE NOCASE ASC',
    ).get();
    return <Playlist>[
      for (final row in rows)
        Playlist(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          description: row.readNullable<String>('description'),
          coverPath: row.readNullable<String>('cover_path'),
          createdAt: row.read<DateTime>('created_at'),
          updatedAt: row.read<DateTime>('updated_at'),
          itemCount: row.read<int>('item_count'),
        ),
    ];
  }

  /// Creates a playlist and returns its id.
  Future<int> createPlaylist(String name, {String? description}) {
    final now = DateTime.now();
    return into(playlists).insert(
      PlaylistsCompanion.insert(
        name: name,
        description: Value(description),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Renames a playlist and bumps `updatedAt`.
  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((p) => p.id.equals(id))).write(
        PlaylistsCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
      );

  /// Deletes a playlist (items cascade via FK).
  Future<void> deletePlaylist(int id) =>
      (delete(playlists)..where((p) => p.id.equals(id))).go();

  /// The tracks of one playlist in persisted position order.
  Future<List<Track>> tracksOf(int playlistId) async {
    final rows = await customSelect(
      'SELECT t.id AS track_id FROM playlist_items pi '
      'JOIN tracks t ON t.id = pi.track_id '
      'WHERE pi.playlist_id = ? '
      'ORDER BY pi.position ASC, pi.id ASC',
      variables: [Variable.withInt(playlistId)],
    ).get();
    final ids = [for (final row in rows) row.read<int>('track_id')];
    if (ids.isEmpty) {
      return const <Track>[];
    }
    final trackRows = await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = <int, TracksRow>{
      for (final row in trackRows) row.id: row,
    };
    return <Track>[
      for (final id in ids)
        if (byId[id] case final row?) TrackMapper.toDomain(row),
    ];
  }

  /// Adds [trackIds] to the end of the playlist. Duplicates are skipped
  /// (unique index) — re-adding existing tracks is a no-op for them.
  Future<void> addTracks(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) {
      return;
    }
    final maxRow = await customSelect(
      'SELECT COALESCE(MAX(position), -1) AS max_pos '
      'FROM playlist_items WHERE playlist_id = ?',
      variables: [Variable.withInt(playlistId)],
    ).getSingle();
    var position = maxRow.read<int>('max_pos') + 1;
    final now = DateTime.now();
    for (final trackId in trackIds) {
      await into(playlistItems).insertOnConflictUpdate(
        PlaylistItemsCompanion.insert(
          playlistId: playlistId,
          trackId: trackId,
          position: position,
          addedAt: now,
        ),
      );
      position++;
    }
    await (update(playlists)..where((p) => p.id.equals(playlistId))).write(
      PlaylistsCompanion(updatedAt: Value(DateTime.now())),
    );
  }

  /// Removes one track from a playlist (keeps the remaining order dense).
  Future<void> removeTrack(int playlistId, int trackId) async {
    final rows = await customSelect(
      'SELECT id, position FROM playlist_items '
      'WHERE playlist_id = ? AND track_id = ? LIMIT 1',
      variables: [
        Variable.withInt(playlistId),
        Variable.withInt(trackId),
      ],
    ).get();
    if (rows.isEmpty) {
      return;
    }
    final rowId = rows.first.read<int>('id');
    final removedPosition = rows.first.read<int>('position');
    await (delete(playlistItems)..where((pi) => pi.id.equals(rowId))).go();
    // Re-pack positions above the removed one.
    final later = await customSelect(
      'SELECT id, position FROM playlist_items '
      'WHERE playlist_id = ? AND position > ? ORDER BY position ASC',
      variables: [
        Variable.withInt(playlistId),
        Variable.withInt(removedPosition),
      ],
    ).get();
    var next = removedPosition;
    for (final row in later) {
      await (update(playlistItems)
            ..where((pi) => pi.id.equals(row.read<int>('id'))))
          .write(PlaylistItemsCompanion(position: Value(next)));
      next++;
    }
  }
}
