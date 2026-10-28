/// authored, awaiting local run.
///
/// Hand-rolled fake `PlaybackEngine` shared by the player widget tests.
/// Records every transport call and lets tests drive the state/position
/// streams the same way the real engines do.
library;

import 'dart:async';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

class FakePlaybackEngine implements PlaybackEngine {
  double lastVolume = 1.0;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  /// Tracks handed to [load] in order.
  final List<Track> loaded = <Track>[];

  /// Start indexes handed to [setQueue] in order.
  final List<int> setQueueStarts = <int>[];

  final List<Duration> seeks = <Duration>[];

  int playCalls = 0;
  int pauseCalls = 0;

  /// When non-null, every transport call throws (engine-failure paths).
  Object? throwOnCall;

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    loaded.add(t);
  }

  @override
  Future<void> play() async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    playCalls++;
    _stateController.add(PlaybackState.playing);
  }

  @override
  Future<void> pause() async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    pauseCalls++;
    _stateController.add(PlaybackState.paused);
  }

  @override
  Future<void> seek(Duration p) async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    seeks.add(p);
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (throwOnCall != null) {
      throw throwOnCall!;
    }
    setQueueStarts.add(startIndex);
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  /// Emits a position tick (simulates playback progress).
  void tickPosition(Duration position) =>
      _positionController.add(position);

  /// Emits an engine lifecycle state (simulates the real engine pipeline).
  void emitState(PlaybackState state) => _stateController.add(state);

    @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
  }

@override
  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
  }
}
