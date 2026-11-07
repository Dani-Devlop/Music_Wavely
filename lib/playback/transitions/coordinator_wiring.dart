/// Wiring for the Phase 8 playback coordinators (function-injected).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/transitions/playback_coordinators.dart';

/// Builds a [ReplayGainPlaybackCoordinator] bound to the app graph.
ReplayGainPlaybackCoordinator buildReplayGainCoordinator(Ref ref) {
  final QueueManager manager = ref.watch(queueManagerProvider.notifier);
  return ReplayGainPlaybackCoordinator(
    queueStream: manager.stream,
    resolveInputs: (Track track) async {
      final AudioEngineState engineState =
          ref.read(audioEngineControllerProvider);
      final ReplayGainMode mode = engineState.settings.replayGainMode;
      final int? trackId = track.id;
      if (mode == ReplayGainMode.off || trackId == null) {
        return ReplayGainInputs(
          mode: mode,
          preampDb: engineState.settings.replayGainPreampDb,
        );
      }
      final AppDatabase db = ref.read(databaseProvider);
      final ReplayGainRow? row = await db.replayGainDao.forTrack(trackId);
      return ReplayGainInputs(
        mode: mode,
        trackGainDb: row?.trackGainDb,
        albumGainDb: row?.albumGainDb,
        peakLinear: row?.peak,
        preampDb: engineState.settings.replayGainPreampDb,
      );
    },
    setVolume: (double volume) async {
      try {
        await ref.read(playbackEngineProvider).setVolume(volume);
      } on Object {
        // Never break playback.
      }
    },
  );
}

/// Builds a [TransitionCoordinator] bound to the app graph.
TransitionCoordinator buildTransitionCoordinator(Ref ref) {
  final QueueManager manager = ref.watch(queueManagerProvider.notifier);
  return TransitionCoordinator(
    queueStream: manager.stream,
    readConfig: () =>
        ref.read(audioEngineControllerProvider).settings.transitions,
    setVolume: (double volume) async {
      try {
        await ref.read(playbackEngineProvider).setVolume(volume);
      } on Object {
        // Never break playback.
      }
    },
  );
}

/// Manual providers (activated once by the app bootstrap; no-op in tests
/// that never touch them).
final replayGainPlaybackCoordinatorProvider =
    Provider<ReplayGainPlaybackCoordinator>(buildReplayGainCoordinator);

final transitionCoordinatorProvider =
    Provider<TransitionCoordinator>(buildTransitionCoordinator);
