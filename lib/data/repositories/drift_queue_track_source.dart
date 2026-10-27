import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Drift-backed [QueueTrackSource] over the `tracks` table.
///
/// Honors the requested id order: [TracksDao.byIds] returns rows in
/// database order, so they are re-keyed by id and replayed following the
/// persisted id sequence. Ids that no longer resolve (deleted tracks) are
/// dropped — the restored queue simply shrinks.
class DriftQueueTrackSource implements QueueTrackSource {
  /// Creates the source over [dao].
  const DriftQueueTrackSource(this._dao);

  final TracksDao _dao;

  @override
  Future<List<Track>> byIds(List<int> ids) async {
    final rows = await _dao.byIds(ids);
    final byId = <int, Track>{
      for (final track in rows)
        if (track.id case final int id?) id: track,
    };
    return <Track>[
      for (final id in ids)
        if (byId[id] case final Track track?) track,
    ];
  }
}
