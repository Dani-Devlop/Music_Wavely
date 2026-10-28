/// Authored, awaiting local run (Task 2-a).
///
/// Hand-rolled fake implementing `lib/playback/engines/playback_engine.dart`'s
/// [PlaybackEngine] contract EXACTLY:
///
/// ```dart
/// Future<void> load(Track t, {Duration? startAt});
/// Future<void> play();
/// Future<void> pause();
/// Future<void> seek(Duration p);
/// Stream<Duration> get positionStream;
/// Stream<PlaybackState> get stateStream;
/// Future<void> setQueue(List<Track> tracks, {int startIndex = 0});
/// Future<void> setVolume(double volume);
/// Future<void> dispose();
/// ```
///
/// Scripting surface:
/// - [emitState] / [emitPosition] / [complete] push engine events; both
///   streams are synchronous broadcast streams so listeners (e.g.
///   [QueueManager], which subscribes in its constructor) receive events in
///   deterministic, same-tick order as long as emission happens AFTER the
///   manager was constructed.
/// - Every method records its call count and last arguments for assertions.
/// - The optional `onLoad` / `onSetQueue` / `onPlay` / `onPause` / `onSeek`
///   hooks let a test simulate engine failures by throwing from inside them
///   (call sites in `queue_manager.dart` and `providers.dart` wrap engine
///   calls in try/catch and surface [PlaybackState.error]).
///
/// Mirrors how the real engines are consumed:
/// - `QueueManager` calls `setQueue(tracks, startIndex:)` to (re)load the
///   current track, `play`/`pause`/`seek`, and mirrors `stateStream`
///   (`completed` drives auto-advance) + `positionStream` into its state.
/// - `playbackEngineProvider` (engine_factory.dart) registers
///   `ref.onDispose(engine.dispose)`; tests override that provider with
///   `overrideWithValue(FakePlaybackEngine())`.

import 'dart:async';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// Hook signature for [FakePlaybackEngine.onLoad].
typedef FakeLoadHook = void Function(Track track, Duration? startAt);

/// Hook signature for [FakePlaybackEngine.onSetQueue].
typedef FakeSetQueueHook = void Function(List<Track> tracks, int startIndex);

/// Scriptable [PlaybackEngine] fake (no mocktail/mockito).
class FakePlaybackEngine implements PlaybackEngine {
  /// Creates the fake. All hooks are optional; throwing from a hook
  /// simulates the corresponding engine failure.
  FakePlaybackEngine({
    this.onLoad,
    this.onSetQueue,
    this.onPlay,
    this.onPause,
    this.onSeek,
  });

  /// Optional load hook — may throw to simulate a failed load.
  final FakeLoadHook? onLoad;

  /// Optional setQueue hook — may throw to simulate a failed queue load.
  final FakeSetQueueHook? onSetQueue;

  /// Optional play hook — may throw to simulate a failed `play()`.
  final void Function()? onPlay;

  /// Optional pause hook — may throw to simulate a failed `pause()`.
  final void Function()? onPause;

  /// Optional seek hook — may throw to simulate a failed `seek()`.
  final void Function()? onSeek;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast(sync: true);

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  // -- recorded interaction -------------------------------------------------

  /// Number of `load()` calls.
  int loadCalls = 0;

  /// Number of `setQueue()` calls.
  int setQueueCalls = 0;

  /// Number of `play()` calls.
  int playCalls = 0;

  /// Number of `pause()` calls.
  int pauseCalls = 0;

  /// Number of `seek()` calls.
  int seekCalls = 0;

  /// Number of `setVolume()` calls.
  int setVolumeCalls = 0;

  /// Number of `dispose()` calls.
  int disposeCalls = 0;

  /// Every seek target, in call order.
  final List<Duration> seeks = <Duration>[];

  /// Track passed to the last `load()` (or the track the last `setQueue()`
  /// pointed at via [lastStartIndex]).
  Track? loadedTrack;

  /// `startAt` passed to the last `load()`.
  Duration? loadedStartAt;

  /// Queue passed to the last `setQueue()`.
  List<Track> lastSetQueue = const <Track>[];

  /// Start index passed to the last `setQueue()`.
  int lastStartIndex = 0;

  // -- observable engine state ----------------------------------------------

  /// True once [dispose] ran.
  bool disposed = false;

  /// Current simulated engine state (kept in sync with [emitState]).
  PlaybackState state = PlaybackState.stopped;

  /// Current simulated playback position (kept in sync with [emitPosition]).
  Duration position = Duration.zero;

  /// Every state pushed through [emitState], in order.
  final List<PlaybackState> stateHistory = <PlaybackState>[];

  /// Every position pushed through [emitPosition], in order.
  final List<Duration> positionHistory = <Duration>[];

  // -- PlaybackEngine contract ----------------------------------------------

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    loadCalls += 1;
    loadedTrack = t;
    loadedStartAt = startAt;
    onLoad?.call(t, startAt);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    onPlay?.call();
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    onPause?.call();
  }

  @override
  Future<void> seek(Duration p) async {
    seekCalls += 1;
    seeks.add(p);
    position = p;
    onSeek?.call();
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    setQueueCalls += 1;
    lastSetQueue = List<Track>.of(tracks);
    lastStartIndex = startIndex;
    if (tracks.isEmpty) {
      loadedTrack = null;
    } else {
      var index = startIndex;
      if (index < 0) {
        index = 0;
      }
      if (index >= tracks.length) {
        index = tracks.length - 1;
      }
      loadedTrack = tracks[index];
    }
    onSetQueue?.call(lastSetQueue, startIndex);
  }

  /// Volume applied by the last [setVolume] call (BUG-9 mute assertions).
  double lastVolume = 1.0;

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls += 1;
    lastVolume = volume;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    disposed = true;
    await _stateController.close();
    await _positionController.close();
  }

  // -- scripting helpers ------------------------------------------------------

  /// Pushes [s] onto [stateStream] and records it.
  ///
  /// No-op after [dispose] (closed controllers would throw).
  void emitState(PlaybackState s) {
    if (_stateController.isClosed) {
      return;
    }
    state = s;
    stateHistory.add(s);
    _stateController.add(s);
  }

  /// Pushes [p] onto [positionStream] and records it.
  ///
  /// No-op after [dispose].
  void emitPosition(Duration p) {
    if (_positionController.isClosed) {
      return;
    }
    position = p;
    positionHistory.add(p);
    _positionController.add(p);
  }

  /// Emulates the track finishing: emits [PlaybackState.completed]
  /// (QueueManager reacts with auto-advance / repeat / rest-in-completed).
  void complete() => emitState(PlaybackState.completed);

  /// Emulates an engine failure the way real engines report it: as an
  /// [PlaybackState.error] event (NOT as a stream error — stream errors
  /// would surface as unhandled async exceptions in consumers).
  void fail() => emitState(PlaybackState.error);
}
