// authored, awaiting local run.
//
// QueueTrackLauncher tests (`lib/data/repositories/queue_track_launcher.dart`):
// the TrackLauncher adapter that hands track lists to a real QueueManager
// (driven by a hand-rolled recording fake engine + in-memory settings
// store). Covers the interface conformance, the setQueue + play
// delegation with an explicit startIndex, the default startIndex and
// queue replacement across calls.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/repositories/queue_track_launcher.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

class _RecordingEngine implements PlaybackEngine {
  double lastVolume = 1.0;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();

  final List<List<Track>> setQueueTracks = <List<Track>>[];
  final List<int> setQueueStarts = <int>[];
  final List<Track> loadCalls = <Track>[];
  int playCalls = 0;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    loadCalls.add(t);
    _states.add(PlaybackState.loading);
    _states.add(PlaybackState.paused);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _states.add(PlaybackState.playing);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration p) async {}

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
    await _states.close();
    await _positions.close();
  }
}

Track _track(int id) => Track(
      id: id,
      sourceId: Track.localSourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: 'Artist',
      durationMs: 60000,
      format: 'mp3',
      filePath: '/audio/$id.mp3',
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

List<Track> _pool(int count) => <Track>[
      for (var i = 1; i <= count; i++) _track(i),
    ];

void main() {
  late _RecordingEngine engine;
  late QueueManager manager;
  late QueueTrackLauncher launcher;
  final started = <Track>[];

  setUp(() {
    engine = _RecordingEngine();
    started.clear();
  });

  tearDown(() async {
    await manager.dispose();
    await engine.dispose();
  });

  test('satisfies the TrackLauncher port', () {
    manager = QueueManager(
      engine: engine,
      store: InMemorySettingsStore(),
      onTrackStarted: started.add,
    );
    final QueueTrackLauncher adapter = QueueTrackLauncher(manager);
    final TrackLauncher port = adapter; // static conformance
    expect(port, same(adapter));
  });

  test('playTracks delegates setQueue + play with the given startIndex',
      () async {
    final pool = _pool(3);
    manager = QueueManager(
      engine: engine,
      store: InMemorySettingsStore(),
      onTrackStarted: started.add,
    );
    launcher = QueueTrackLauncher(manager);

    await launcher.playTracks(pool, startIndex: 1);
    await pumpEventQueue();

    expect(manager.state.tracks.map((t) => t.id),
        orderedEquals(pool.map((t) => t.id)));
    expect(manager.state.currentIndex, 1);
    expect(manager.state.playbackState, PlaybackState.playing);
    expect(engine.setQueueTracks.single, pool);
    expect(engine.setQueueStarts.single, 1);
    expect(engine.playCalls, 1);
    expect(started.map((t) => t.id), <int>[2]);
  });

  test('playTracks defaults to startIndex 0', () async {
    final pool = _pool(3);
    manager = QueueManager(
      engine: engine,
      store: InMemorySettingsStore(),
      onTrackStarted: started.add,
    );
    launcher = QueueTrackLauncher(manager);

    await launcher.playTracks(pool);
    await pumpEventQueue();

    expect(manager.state.currentIndex, 0);
    expect(engine.setQueueStarts.single, 0);
    expect(started.map((t) => t.id), <int>[1]);
  });

  test('a second playTracks replaces the whole queue', () async {
    manager = QueueManager(
      engine: engine,
      store: InMemorySettingsStore(),
      onTrackStarted: started.add,
    );
    launcher = QueueTrackLauncher(manager);

    await launcher.playTracks(_pool(3));
    await launcher.playTracks(_pool(2), startIndex: 1);
    await pumpEventQueue();

    expect(manager.state.tracks.map((t) => t.id), <int>[1, 2]);
    expect(manager.state.currentIndex, 1);
    expect(engine.setQueueTracks, hasLength(2));
    expect(started.map((t) => t.id), <int>[1, 2]);
  });
}
