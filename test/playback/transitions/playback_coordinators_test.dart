/// Tests for the Phase 8 playback coordinators (ReplayGain application +
/// crossfade envelope) — pure function injection, no provider graph.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/transitions/playback_coordinators.dart';
import 'package:wavely/playback/transitions/transition_planner.dart';
import '../../support/track_factory.dart';

/// Tracks pushed volumes.
class VolumeRecorder {
  final List<double> volumes = <double>[];

  Future<void> write(double volume) async {
    volumes.add(volume);
  }
}

/// Emits QueueState snapshots like QueueManager does.
class QueueStateSource {
  final StreamController<QueueState> _controller =
      StreamController<QueueState>.broadcast();

  Stream<QueueState> get stream => _controller.stream;

  QueueState _state = const QueueState(
    position: Duration.zero,
    duration: Duration.zero,
  );

  QueueState get state => _state;

  void emit(QueueState next) {
    _state = next;
    _controller.add(next);
  }

  void close() => _controller.close();
}

QueueState queueOf(
  Track? track, {
  int index = 0,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
}) =>
    QueueState(
      tracks: track == null ? const <Track>[] : <Track>[track],
      currentIndex: index,
      position: position,
      duration: duration,
    );

void main() {
  group('ReplayGainPlaybackCoordinator', () {
    test('applies the track gain multiplier on track change', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(1, id: 101, filePath: '/music/a.mp3');

      final ReplayGainPlaybackCoordinator coordinator =
          ReplayGainPlaybackCoordinator(
        queueStream: source.stream,
        resolveInputs: (Track _) async => const ReplayGainInputs(
          mode: ReplayGainMode.track,
          trackGainDb: -20, // ×0.1
          peakLinear: 0.5,
        ),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(queueOf(track));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes, isNotEmpty);
      expect(recorder.volumes.last, closeTo(0.1, 0.001));
    });

    test('mode off resets volume to unity', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(2, id: 202, filePath: '/music/b.mp3');

      final ReplayGainPlaybackCoordinator coordinator =
          ReplayGainPlaybackCoordinator(
        queueStream: source.stream,
        resolveInputs: (Track _) async =>
            const ReplayGainInputs(mode: ReplayGainMode.off, trackGainDb: -20),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(queueOf(track));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes.last, 1.0);
    });

    test('unmeasured tracks keep unity volume', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(3, id: 303, filePath: '/music/c.mp3');

      final ReplayGainPlaybackCoordinator coordinator =
          ReplayGainPlaybackCoordinator(
        queueStream: source.stream,
        resolveInputs: (Track _) async =>
            const ReplayGainInputs(mode: ReplayGainMode.track),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(queueOf(track));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes.last, 1.0);
    });

    test('resolveInputs failure degrades to unity, never throws',
        () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(4, id: 404, filePath: '/music/d.mp3');

      final ReplayGainPlaybackCoordinator coordinator =
          ReplayGainPlaybackCoordinator(
        queueStream: source.stream,
        resolveInputs: (Track _) => throw StateError('db down'),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(queueOf(track));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes.last, 1.0);
    });

    test('same track twice does not re-apply', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(5, id: 505, filePath: '/music/e.mp3');

      final ReplayGainPlaybackCoordinator coordinator =
          ReplayGainPlaybackCoordinator(
        queueStream: source.stream,
        resolveInputs: (Track _) async => const ReplayGainInputs(
          mode: ReplayGainMode.track,
          trackGainDb: -20,
        ),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(queueOf(track, position: Duration.zero));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final int afterFirst = recorder.volumes.length;

      // Position-only update (same track) → no new volume write.
      source.emit(
        queueOf(track, position: const Duration(seconds: 1)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recorder.volumes.length, afterFirst);
    });
  });

  group('TransitionCoordinator', () {
    test('crossfade window drives a fade-out envelope', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(
        6,
        id: 606,
        filePath: '/music/f.mp3',
        durationMs: 60000,
      );

      final TransitionCoordinator coordinator = TransitionCoordinator(
        queueStream: source.stream,
        readConfig: () =>
            const TransitionConfig(crossfadeSeconds: 10, gapless: true),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      // Enter the track (new index opens the fade-in window).
      source.emit(
        queueOf(
          track,
          position: Duration.zero,
          duration: const Duration(seconds: 60),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Deep inside the fade-out window.
      source.emit(
        queueOf(
          track,
          position: const Duration(seconds: 59, milliseconds: 500),
          duration: const Duration(seconds: 60),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes, isNotEmpty);
      expect(recorder.volumes.last, lessThan(0.2));
    });

    test('crossfade off keeps unity volume everywhere', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(
        7,
        id: 707,
        filePath: '/music/g.mp3',
        durationMs: 60000,
      );

      final TransitionCoordinator coordinator = TransitionCoordinator(
        queueStream: source.stream,
        readConfig: () => const TransitionConfig(crossfadeSeconds: 0),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      source.emit(
        queueOf(
          track,
          position: const Duration(seconds: 59, milliseconds: 500),
          duration: const Duration(seconds: 60),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(recorder.volumes, isEmpty);
    });

    test('readConfig failure never throws into the stream', () async {
      final VolumeRecorder recorder = VolumeRecorder();
      final QueueStateSource source = QueueStateSource();
      addTearDown(source.close);
      final Track track = seedTrack(
        8,
        id: 808,
        filePath: '/music/h.mp3',
        durationMs: 60000,
      );

      final TransitionCoordinator coordinator = TransitionCoordinator(
        queueStream: source.stream,
        readConfig: () => throw StateError('no profile'),
        setVolume: recorder.write,
      );
      addTearDown(coordinator.dispose);

      // Must not throw synchronously nor asynchronously.
      source.emit(
        queueOf(
          track,
          position: const Duration(seconds: 59),
          duration: const Duration(seconds: 60),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(recorder.volumes, isEmpty);
    });
  });
}
