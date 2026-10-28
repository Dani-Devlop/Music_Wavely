// authored, awaiting local run.
//
// PlaybackEngine contract suite (`lib/playback/engines/playback_engine.dart`)
// exercised against a scripted reference fake. Pins the documented state
// machine (load -> ready/paused -> playing -> paused -> completed), the
// ArgumentError contract for tracks without a local file, single-track
// setQueue semantics, monotonic scripted position delivery and dispose
// idempotency. The real engines (media_kit / just_audio / web) are covered
// on-device — see engine_contract_smoke_test.dart for the guarded factory
// smoke pair.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// Scripted fake implementing [PlaybackEngine] exactly like the real
/// engines do: `load` emits loading -> paused (ready), `play`/`pause`
/// mirror into the state stream, `dispose` is guarded and idempotent.
class _ScriptedEngine implements PlaybackEngine {
  double lastVolume = 1.0;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();

  final List<Track> loadCalls = <Track>[];
  final List<Duration?> startAtCalls = <Duration?>[];
  final List<Duration> seekCalls = <Duration>[];
  final List<Duration> positionTicks = <Duration>[];
  final List<List<Track>> setQueueCalls = <List<Track>>[];
  final List<int> setQueueStarts = <int>[];
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  void emitState(PlaybackState s) => _states.add(s);

  void tickPosition(Duration p) {
    positionTicks.add(p);
    _positions.add(p);
  }

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    if (t.filePath == null || t.filePath!.isEmpty) {
      // The documented contract: throwing keeps the guard explicit.
      throw ArgumentError.value(t, 't', 'Track has no local filePath');
    }
    loadCalls.add(t);
    startAtCalls.add(startAt);
    _states.add(PlaybackState.loading);
    _states.add(PlaybackState.paused);
  }

  @override
  Future<void> play() async {
    if (disposed) {
      return;
    }
    playCalls++;
    _states.add(PlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    if (disposed) {
      return;
    }
    pauseCalls++;
    _states.add(PlaybackState.paused);
  }

  @override
  Future<void> seek(Duration p) async {
    if (disposed) {
      return;
    }
    seekCalls.add(p);
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    setQueueCalls.add(List<Track>.of(tracks));
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
    if (disposed) {
      return; // idempotent
    }
    disposed = true;
    await _states.close();
    await _positions.close();
  }
}

/// Sentinel so `_track(2, filePath: null)` produces a REAL null path
/// (a plain `?? default` would silently substitute it back).
const String _kDefaultPath = '#default';

Track _track(int id, {Object? filePath = _kDefaultPath}) => Track(
      id: id,
      sourceId: Track.localSourceId,
      sourceTrackId: 'src-$id',
      title: 'Track $id',
      artist: 'Artist',
      durationMs: 60000,
      format: 'mp3',
      filePath: filePath == _kDefaultPath
          ? '/audio/$id.mp3'
          : filePath as String?,
      addedAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

bool _isMonotonic(List<Duration> xs) {
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] < xs[i - 1]) {
      return false;
    }
  }
  return true;
}

void main() {
  late _ScriptedEngine engine;

  setUp(() {
    engine = _ScriptedEngine();
  });

  tearDown(() async {
    await engine.dispose();
  });

  test('contract enums expose the documented values', () {
    expect(PlaybackState.values, <PlaybackState>[
      PlaybackState.stopped,
      PlaybackState.loading,
      PlaybackState.buffering,
      PlaybackState.playing,
      PlaybackState.paused,
      PlaybackState.completed,
      PlaybackState.error,
    ]);
    expect(RepeatMode.values, <RepeatMode>[
      RepeatMode.off,
      RepeatMode.all,
      RepeatMode.one,
    ]);
  });

  group('documented state machine', () {
    test('load -> ready(paused) -> play -> pause -> play -> completed',
        () async {
      final states = <PlaybackState>[];
      final sub = engine.stateStream.listen(states.add);
      final track = _track(1);

      await engine.load(track);
      await engine.play();
      await engine.pause();
      await engine.play();
      engine.emitState(PlaybackState.completed);
      await pumpEventQueue();

      expect(states, <PlaybackState>[
        PlaybackState.loading,
        PlaybackState.paused,
        PlaybackState.playing,
        PlaybackState.paused,
        PlaybackState.playing,
        PlaybackState.completed,
      ]);
      expect(engine.playCalls, 2);
      expect(engine.pauseCalls, 1);
      await sub.cancel();
    });

    test('load without a local file path throws ArgumentError', () async {
      await expectLater(
        engine.load(_track(2, filePath: null)),
        throwsArgumentError,
      );
      await expectLater(
        engine.load(_track(3, filePath: '')),
        throwsArgumentError,
      );
      expect(engine.loadCalls, isEmpty);
    });

    test('load forwards the optional start position', () async {
      const start = Duration(seconds: 30);
      await engine.load(_track(4), startAt: start);
      expect(engine.startAtCalls.single, start);
      await engine.load(_track(5));
      expect(engine.startAtCalls.last, isNull);
    });
  });

  group('position stream', () {
    test('delivers the scripted ticks verbatim and in monotonic order',
        () async {
      final received = <Duration>[];
      final sub = engine.positionStream.listen(received.add);
      final script = <Duration>[
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      ];
      for (final tick in script) {
        engine.tickPosition(tick);
      }
      await pumpEventQueue();

      expect(received, orderedEquals(script));
      expect(_isMonotonic(received), isTrue);
      await sub.cancel();
    });
  });

  group('single-track setQueue semantics', () {
    test('stores the queue and loads only the start track', () async {
      final tracks = <Track>[_track(1), _track(2), _track(3)];
      await engine.setQueue(tracks, startIndex: 2);
      expect(engine.setQueueCalls.single, tracks);
      expect(engine.setQueueStarts.single, 2);
      expect(engine.loadCalls.single, tracks[2]);
    });

    test('empty queue stores nothing playable and loads nothing', () async {
      await engine.setQueue(const <Track>[]);
      expect(engine.setQueueCalls, hasLength(1));
      expect(engine.loadCalls, isEmpty);
    });

    test('out-of-range start index is clamped, never throws', () async {
      final tracks = <Track>[_track(1), _track(2)];
      await engine.setQueue(tracks, startIndex: 42);
      expect(engine.loadCalls.single, tracks[1]);
      await engine.setQueue(tracks, startIndex: -1);
      expect(engine.loadCalls.last, tracks[0]);
    });
  });

  group('dispose contract', () {
    test('dispose is idempotent and closes both streams', () async {
      await engine.dispose();
      await engine.dispose(); // second call must not throw
      expect(engine.disposed, isTrue);
      await expectLater(engine.stateStream, emitsDone);
      await expectLater(engine.positionStream, emitsDone);
    });

    test('transport calls after dispose are silent no-ops', () async {
      await engine.dispose();
      await engine.play();
      await engine.pause();
      await engine.seek(const Duration(seconds: 1));
      expect(engine.playCalls, 0);
      expect(engine.pauseCalls, 0);
      expect(engine.seekCalls, isEmpty);
    });
  });
}
