import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Records one listening session per started track into the `plays` table.
///
/// Bound by [playRecorderProvider] and invoked through QueueManager's
/// `onTrackStarted` hook (composition-root wiring in
/// `lib/app/providers.dart`). Tracks without a database id (not yet
/// persisted) are skipped — the id is the foreign key.
class PlayRecorder {
  /// Creates the recorder over [playsDao]; [deviceId] overrides the default
  /// per-install identifier (the current target platform name until a
  /// stable device-id feature lands in a later stage).
  PlayRecorder(this._playsDao, {String? deviceId}) : _deviceId = deviceId;

  final PlaysDao _playsDao;
  final String? _deviceId;

  /// Records the start of a listening session for [track]. DAO failures
  /// propagate: QueueManager already wraps the onTrackStarted hook in its
  /// own guard (see queue_manager_test.dart), so a recorder crash can never
  /// break playback — the single guard point is the caller, not this class.
  Future<void> record(Track track) async {
    final trackId = track.id;
    if (trackId == null) {
      return;
    }
    await _playsDao.insertPlay(
      PlaysCompanion.insert(
        trackId: trackId,
        startedAt: DateTime.now(),
        listenedMs: 0,
        completed: const Value(false),
        source: track.sourceId,
        deviceId: _deviceId ?? PlatformUtils.currentTargetPlatform.name,
      ),
    );
  }
}

/// Composition-root binding over the app database's plays DAO.
final playRecorderProvider = Provider<PlayRecorder>((ref) {
  return PlayRecorder(ref.watch(databaseProvider).playsDao);
});
