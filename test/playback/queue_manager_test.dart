// authored, awaiting local run.
//
// QueueManager suite (`lib/playback/queue/queue_manager.dart`) over a
// hand-rolled recording fake engine, an in-memory SettingsStore and a fake
// QueueTrackSource. Covers: queue loading/clamping, play/pause/toggle,
// next/previous with all three RepeatMode wrap-around semantics, seek, the
// onTrackStarted record-play hook (once per track start, recorder failures
// swallowed), shuffle on/off (+ advanced ShuffleConfig integration), the
// TrackLoadDecision parental skip-chain (skip -> advance, replace ->
// censored path, bounded so an all-blocked queue rests in completed),
// speed / sleep-timer state passthrough, persistence-driven restore and
// queue mutations.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';

/// Records every engine interaction; mirrors the real single-track-loader
/// semantics (setQueue stores the list and loads `tracks[startIndex]`).
class _RecordingEngine implements PlaybackEngine {
  double lastVolume = 1.0;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();

  final List<List<Track>> setQueueTracks = <List<Track>>[];
  final List<int> setQueueStarts = <int>[];
  final List<Track> loadCalls = <Track>[];
  final List<Duration> seekCalls = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;
  Object? playError;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  void emitState(PlaybackState s) => _states.add(s);

  void emitPosition(Duration p) => _positions.add(p);

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    loadCalls.add(t);
    _states.add(PlaybackState.loading);
    _states.add(PlaybackState.paused);
  }

  @override
  Future<void> play() async {
    final error = playError;
    if (error != null) {
      throw error;
    }
    playCalls++;
    _states.add(PlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _states.add(PlaybackState.paused);
  }

  @override
  Future<void> seek(Duration p) async {
    seekCalls.add(p);
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    setQueueTracks.add(List<Track>.of(tracks));
    setQueueStarts.add(startIndex);
    if (tracks.isEmpty) {
      return;
    }
    var index = startIndex;
    if (index < 0) {
      index = 0;
    }
    if (index >= tracks.length) {
      index = tracks.length - 1;
    }
    await load(tracks[index]);
  }

    @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

@override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
    await _positions.close();
  }
}

class _FakeTrackSource implements QueueTrackSource {
  _FakeTrackSource(this._resolver);

  final Future<List<Track>> Function(List<int> ids) _resolver;
  final List<List<int>> calls = <List<int>>[];

  @override
  Future<List<Track>> byIds(List<int> ids) {
    calls.add(List<int>.of(ids));
    return _resolver(ids);
  }
}

Track _track(
  int id, {
  String? genre,
  String artist = 'Artist',
  int durationMs = 60000,
}) =>
    Track(
      id: id,
      sourceId: Track.localSourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: artist,
      genre: genre,
      durationMs: durationMs,
      format: 'mp3',
      filePath: '/audio/$id.mp3',
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

List<Track> _pool(int count, {int durationMs = 60000}) => <Track>[
      for (var i = 1; i <= count; i++)
        _track(i, durationMs: durationMs + i),
    ];

QueueManager _manager(
  _RecordingEngine engine, {
  QueueTrackSource? trackSource,
  void Function(Track track)? onTrackStarted,
  ShuffleConfig? advancedShuffleConfig,
  Future<TrackLoadDecision?> Function(Track track)? trackPreloadHook,
  SettingsStore? store,
}) =>
    QueueManager(
      engine: engine,
      store: store ?? InMemorySettingsStore(),
      trackSource: trackSource,
      onTrackStarted: onTrackStarted,
      advancedShuffleConfig: advancedShuffleConfig,
      trackPreloadHook: trackPreloadHook,
    );

void main() {
  late _RecordingEngine engine;
  late QueueManager manager;
  final started = <Track>[];

  setUp(() {
    engine = _RecordingEngine();
    started.clear();
  });

  tearDown(() async {
    manager.dispose();
    await engine.dispose();
  });

  group('queue loading', () {
    test('setQueue loads the start track through the engine contract',
        () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 1);
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(manager.state.currentTrack, pool[1]);
      expect(
        manager.state.duration,
        Duration(milliseconds: pool[1].durationMs),
      );
      expect(engine.setQueueTracks.single, pool);
      expect(engine.setQueueStarts.single, 1);
      expect(engine.loadCalls.single, pool[1]);
      // A paused load records nothing yet.
      expect(started, isEmpty);
    });

    test('setQueue clamps an out-of-range startIndex', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 99);
      await pumpEventQueue();
      expect(manager.state.currentIndex, 2);

      await manager.setQueue(pool, startIndex: -5);
      await pumpEventQueue();
      expect(manager.state.currentIndex, 0);
      expect(engine.setQueueStarts, <int>[2, 0]);
    });

    test('setQueue with an empty list stops without touching the engine',
        () async {
      manager = _manager(engine);
      await manager.setQueue(const <Track>[]);
      await pumpEventQueue();

      expect(manager.state.tracks, isEmpty);
      expect(manager.state.hasCurrent, isFalse);
      expect(manager.state.playbackState, PlaybackState.stopped);
      expect(engine.setQueueTracks, isEmpty);
      expect(engine.loadCalls, isEmpty);
    });
  });

  group('play / pause / toggle', () {
    test('play flips the state and fires onTrackStarted once', () async {
      final pool = _pool(2);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.play();
      await pumpEventQueue();

      expect(manager.state.playbackState, PlaybackState.playing);
      expect(engine.playCalls, 1);
      expect(started.map((t) => t.id), <int>[1]);
    });

    test('playing again while playing does not re-fire the hook', () async {
      final pool = _pool(2);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.play();
      await manager.play();
      await pumpEventQueue();

      expect(engine.playCalls, 2);
      expect(started, hasLength(1));
    });

    test('pause flips the state and calls the engine', () async {
      final pool = _pool(2);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      await manager.pause();
      await pumpEventQueue();

      expect(manager.state.playbackState, PlaybackState.paused);
      expect(engine.pauseCalls, 1);
    });

    test('togglePlayPause alternates between play and pause', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.togglePlayPause(); // stopped -> play
      expect(manager.state.playbackState, PlaybackState.playing);

      await manager.togglePlayPause(); // playing -> pause
      expect(manager.state.playbackState, PlaybackState.paused);
      expect(engine.playCalls, 1);
      expect(engine.pauseCalls, 1);
    });

    test('an engine play failure degrades to the error state', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();
      engine.playError = Exception('broken sink');

      await manager.play();
      expect(manager.state.playbackState, PlaybackState.error);
    });

    test('playback commands without a queue are no-ops', () async {
      manager = _manager(engine);
      await manager.play();
      await manager.pause();
      await manager.togglePlayPause();
      expect(engine.playCalls, 0);
      expect(engine.pauseCalls, 0);
      expect(manager.state.playbackState, PlaybackState.stopped);
    });
  });

  group('next / previous (wrap-around semantics)', () {
    test('next advances, reloads and auto-plays the next track', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      await manager.next();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(manager.state.playbackState, PlaybackState.playing);
      expect(engine.setQueueStarts.last, 1);
      expect(started.map((t) => t.id), <int>[1, 2]);
    });

    test('next with repeat one restarts the current track', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      manager.setRepeatMode(RepeatMode.one);

      await manager.next();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 0);
      expect(engine.seekCalls, contains(Duration.zero));
      expect(engine.playCalls, greaterThanOrEqualTo(2));
      // Same track -> still exactly one recorded start.
      expect(started.map((t) => t.id), <int>[1]);
    });

    test('next at the end with repeat all wraps to index 0', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool, startIndex: 2);
      manager.setRepeatMode(RepeatMode.all);

      await manager.next();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 0);
      expect(started.map((t) => t.id), <int>[1]);
    });

    test('next at the end with repeat off rests in completed', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 2);
      await pumpEventQueue();

      await manager.next();

      expect(manager.state.playbackState, PlaybackState.completed);
      expect(manager.state.currentIndex, 2);
      expect(manager.state.position, manager.state.duration);
      expect(engine.setQueueStarts, hasLength(1)); // no reload
    });

    test('previous mid-track restarts the current track', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 1);
      await pumpEventQueue();

      await manager.seek(const Duration(seconds: 5));
      await manager.previous();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(engine.seekCalls.last, Duration.zero);
    });

    test('previous at the start wraps with repeat all', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await pumpEventQueue();
      manager.setRepeatMode(RepeatMode.all);

      await manager.previous();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 2);
      expect(started.map((t) => t.id), <int>[3]);
    });

    test('previous at the start without repeat all seeks to zero', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.previous();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 0);
      expect(engine.seekCalls.last, Duration.zero);
      expect(engine.setQueueStarts, hasLength(1));
    });

    test('previous steps back one track when near the start', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool, startIndex: 2);
      await pumpEventQueue();

      await manager.previous();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(started.map((t) => t.id), <int>[2]);
    });
  });

  group('seek', () {
    test('seek mirrors the position into state and the engine', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.seek(const Duration(seconds: 12));
      expect(manager.state.position, const Duration(seconds: 12));
      expect(engine.seekCalls.last, const Duration(seconds: 12));
    });

    test('engine position ticks flow into the queue state', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      engine.emitPosition(const Duration(milliseconds: 2500));
      await pumpEventQueue();
      expect(manager.state.position, const Duration(milliseconds: 2500));
    });
  });

  group('record-play hook (onTrackStarted)', () {
    test('engine completion auto-advances and records the new track once',
        () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      await pumpEventQueue();

      engine.emitState(PlaybackState.completed);
      await pumpEventQueue();
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(started.map((t) => t.id), <int>[1, 2]);
    });

    test('a throwing recorder never breaks playback', () async {
      final pool = _pool(2);
      manager = _manager(
        engine,
        onTrackStarted: (track) => throw StateError('recorder exploded'),
      );
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.play();
      await pumpEventQueue();

      expect(manager.state.playbackState, PlaybackState.playing);
      expect(engine.playCalls, 1);
    });
  });

  group('shuffle on/off', () {
    test('toggleShuffle keeps the multiset and anchors the current track',
        () async {
      final pool = _pool(6);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      await manager.toggleShuffle();
      await pumpEventQueue();

      final state = manager.state;
      expect(state.shuffleEnabled, isTrue);
      expect(state.currentIndex, 0);
      expect(state.tracks.first.id, pool[0].id);
      expect(state.tracks.map((t) => t.id).toSet(),
          pool.map((t) => t.id).toSet());
    });

    test('toggling shuffle off restores the original order and index',
        () async {
      final pool = _pool(6);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 2);
      await pumpEventQueue();

      await manager.toggleShuffle();
      await manager.next(); // move within the shuffled queue
      await pumpEventQueue();
      await manager.toggleShuffle();
      await pumpEventQueue();

      expect(manager.state.shuffleEnabled, isFalse);
      expect(manager.state.tracks.map((t) => t.id),
          orderedEquals(pool.map((t) => t.id)));
      expect(manager.state.currentIndex, 2);
    });

    test('toggleShuffle on an empty queue is a no-op', () async {
      manager = _manager(engine);
      await manager.setQueue(const <Track>[]);
      await manager.toggleShuffle();
      expect(manager.state.shuffleEnabled, isFalse);
    });

    test('advancedShuffleConfig drives the reorder deterministically',
        () async {
      List<Track> buildPool() => <Track>[
            _track(1, genre: 'rock'),
            _track(2, genre: 'metal'),
            _track(3, genre: 'pop'),
            _track(4, genre: 'metal'),
            _track(5, genre: 'jazz'),
            _track(6, genre: 'rock'),
          ];
      const config = ShuffleConfig(blockedGenres: {'metal'}, seed: 7);

      final engineA = _RecordingEngine();
      final engineB = _RecordingEngine();
      final managerA = _manager(engineA, advancedShuffleConfig: config);
      final managerB = _manager(engineB, advancedShuffleConfig: config);
      manager = managerA; // tearDown disposes managerA
      await managerA.setQueue(buildPool());
      await managerB.setQueue(buildPool());
      await managerA.toggleShuffle();
      await managerB.toggleShuffle();
      await pumpEventQueue();

      final idsA = managerA.state.tracks.map((t) => t.id).toList();
      final idsB = managerB.state.tracks.map((t) => t.id).toList();
      expect(idsA, orderedEquals(idsB)); // same seed -> same order
      expect(idsA.first, 1); // current track anchors at 0
      expect(idsA.contains(2), isFalse, reason: 'metal is filtered out');
      expect(idsA.contains(4), isFalse, reason: 'metal is filtered out');
      expect(managerA.state.shuffleEnabled, isTrue);

      managerB.dispose();
      await engineA.dispose();
      await engineB.dispose();
    });
  });

  group('repeat mode / speed / sleep timer passthrough', () {
    test('setRepeatMode and setSpeed are tracked in queue state', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);

      manager.setRepeatMode(RepeatMode.all);
      expect(manager.state.repeatMode, RepeatMode.all);
      manager.setRepeatMode(RepeatMode.one);
      expect(manager.state.repeatMode, RepeatMode.one);

      manager.setSpeed(1.5);
      expect(manager.state.speed, 1.5);
      // No engine rate API in the Stage 1.1 contract.
      expect(engine.playCalls, 0);
      expect(engine.pauseCalls, 0);
    });

    test('an elapsed sleep timer pauses playback and clears the deadline',
        () async {
      final pool = _pool(2);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      await pumpEventQueue();

      manager.startSleepTimer(const Duration(milliseconds: 30));
      expect(manager.state.sleepTimerEndsAt, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 90));
      await pumpEventQueue();

      expect(manager.state.sleepTimerEndsAt, isNull);
      expect(manager.state.playbackState, PlaybackState.paused);
      expect(engine.pauseCalls, 1);
    });

    test('cancelSleepTimer clears the deadline without pausing', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await manager.play();
      await pumpEventQueue();

      manager.startSleepTimer(const Duration(milliseconds: 400));
      manager.cancelSleepTimer();

      expect(manager.state.sleepTimerEndsAt, isNull);
      expect(manager.state.playbackState, PlaybackState.playing);
    });
  });

  group('TrackLoadDecision preload hook (parental seam)', () {
    test('skip advances to the next candidate track', () async {
      final pool = _pool(3);
      manager = _manager(
        engine,
        trackPreloadHook: (track) async =>
            track.id == 1 ? const TrackLoadDecision.skip() : null,
      );
      await manager.setQueue(pool);
      await pumpEventQueue();

      expect(manager.state.currentIndex, 1);
      expect(engine.setQueueStarts.single, 1);
      expect(engine.loadCalls.single, pool[1]);
      expect(manager.state.playbackState, isNot(PlaybackState.completed));
    });

    test('an all-blocked queue rests in completed without loading',
        () async {
      final pool = _pool(3);
      manager = _manager(
        engine,
        trackPreloadHook: (track) async => const TrackLoadDecision.skip(),
      );
      await manager.setQueue(pool);

      expect(manager.state.playbackState, PlaybackState.completed);
      expect(engine.setQueueTracks, isEmpty);
      expect(engine.loadCalls, isEmpty);
    });

    test('replace loads the censored file path instead', () async {
      final pool = _pool(2);
      manager = _manager(
        engine,
        trackPreloadHook: (track) async =>
            track.id == 1
                ? const TrackLoadDecision.replace('/tmp/censored.m4a')
                : null,
      );
      await manager.setQueue(pool);
      await pumpEventQueue();

      expect(engine.loadCalls.single.filePath, '/tmp/censored.m4a');
      // The queue state keeps the original path; only the engine load uses
      // the replacement.
      expect(manager.state.currentTrack!.filePath, '/audio/1.mp3');
    });

    test('a null decision behaves like allow', () async {
      final pool = _pool(2);
      manager = _manager(
        engine,
        trackPreloadHook: (track) async => null,
      );
      await manager.setQueue(pool);
      await pumpEventQueue();

      expect(manager.state.currentIndex, 0);
      expect(engine.setQueueStarts, <int>[0]);
    });

    test('a throwing hook degrades to allow (playback never bricks)',
        () async {
      final pool = _pool(2);
      manager = _manager(
        engine,
        trackPreloadHook: (track) async =>
            throw StateError('parental filter crashed'),
      );
      await manager.setQueue(pool);
      await pumpEventQueue();

      expect(manager.state.currentIndex, 0);
      expect(engine.setQueueStarts, <int>[0]);
      expect(manager.state.playbackState, isNot(PlaybackState.error));
    });
  });

  group('restore (persistence)', () {
    test('restore rebuilds the queue from persisted ids, index and position',
        () async {
      final store = InMemorySettingsStore();
      await store.write(AppConstants.queuePersistKey, '10,11');
      await store.write(AppConstants.queueIndexPersistKey, 1);
      await store.write(AppConstants.queuePositionPersistKey, 12345);
      final source = _FakeTrackSource((ids) async => <Track>[
            _track(ids[0]),
            _track(ids[1]),
          ]);
      manager = _manager(engine, trackSource: source, store: store);
      await manager.restore();
      await pumpEventQueue();

      expect(source.calls, <List<int>>[<int>[10, 11]]);
      expect(manager.state.tracks.map((t) => t.id), <int>[10, 11]);
      expect(manager.state.currentIndex, 1);
      expect(manager.state.position, const Duration(milliseconds: 12345));
      // Restore never auto-plays: no recorded start.
      expect(started, isEmpty);
      expect(engine.setQueueStarts.last, 1);
    });

    test('restore is a no-op without persisted ids or resolvable tracks',
        () async {
      final store = InMemorySettingsStore();
      final source = _FakeTrackSource((ids) async => <Track>[]);
      manager = _manager(engine, trackSource: source, store: store);
      await manager.restore();
      expect(manager.state.tracks, isEmpty);
      expect(source.calls, isEmpty);

      // With ids but an empty resolution the queue also stays empty.
      await store.write(AppConstants.queuePersistKey, '404');
      final sourceEmpty = _FakeTrackSource((ids) async => <Track>[]);
      final manager2 =
          _manager(engine, trackSource: sourceEmpty, store: store);
      await manager2.restore();
      expect(manager2.state.tracks, isEmpty);
      manager2.dispose();
    });

    test('restore survives a failing track source', () async {
      final store = InMemorySettingsStore();
      await store.write(AppConstants.queuePersistKey, '1,2');
      final source = _FakeTrackSource((ids) async => throw StateError('db'));
      manager = _manager(engine, trackSource: source, store: store);
      await manager.restore();
      expect(manager.state.tracks, isEmpty);
      expect(manager.state.playbackState, PlaybackState.stopped);
    });
  });

  group('queue mutations', () {
    test('removing a later row never touches the engine', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();
      final callsBefore = engine.setQueueTracks.length;

      await manager.removeFromQueue(2);
      await pumpEventQueue();

      expect(manager.state.tracks.map((t) => t.id), <int>[1, 2]);
      expect(manager.state.currentIndex, 0);
      expect(engine.setQueueTracks, hasLength(callsBefore));
    });

    test('removing a row before the current one shifts the index', () async {
      final pool = _pool(3);
      manager = _manager(engine);
      await manager.setQueue(pool, startIndex: 2);
      await pumpEventQueue();

      await manager.removeFromQueue(0);
      await pumpEventQueue();

      expect(manager.state.tracks.map((t) => t.id), <int>[2, 3]);
      expect(manager.state.currentIndex, 1);
    });

    test('removing the current row advances and reloads', () async {
      final pool = _pool(3);
      manager = _manager(engine, onTrackStarted: started.add);
      await manager.setQueue(pool);
      await manager.play();
      await pumpEventQueue();

      await manager.removeFromQueue(0);
      await pumpEventQueue();

      expect(manager.state.tracks.map((t) => t.id), <int>[2, 3]);
      expect(manager.state.currentIndex, 0);
      expect(engine.setQueueStarts.last, 0);
      expect(started.map((t) => t.id), <int>[1, 2]);
    });

    test('removing the last remaining row empties and stops', () async {
      final pool = _pool(1);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await manager.play();
      await pumpEventQueue();

      await manager.removeFromQueue(0);
      await pumpEventQueue();

      expect(manager.state.tracks, isEmpty);
      expect(manager.state.playbackState, PlaybackState.stopped);
      expect(engine.pauseCalls, greaterThanOrEqualTo(1));
    });
  });

  group('engine lifecycle bridging', () {
    test('engine error states mirror into the queue state', () async {
      final pool = _pool(2);
      manager = _manager(engine);
      await manager.setQueue(pool);
      await pumpEventQueue();

      engine.emitState(PlaybackState.buffering);
      await pumpEventQueue();
      expect(manager.state.playbackState, PlaybackState.buffering);

      engine.emitState(PlaybackState.error);
      await pumpEventQueue();
      expect(manager.state.playbackState, PlaybackState.error);
    });

    test('engine events for an empty queue are ignored', () async {
      manager = _manager(engine);
      engine.emitState(PlaybackState.playing);
      await pumpEventQueue();
      expect(manager.state.playbackState, PlaybackState.stopped);
    });
  });
}
