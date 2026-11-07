/// Playback-time application of the Phase 8 audio settings.
///
/// Two coordinators (kept in one file — they share the plumbing):
/// - [ReplayGainPlaybackCoordinator]: applies the ReplayGain volume
///   multiplier whenever the current track changes (mode + pre-amp come
///   from the per-device profile, the per-track gain/peak from the
///   `replay_gain_data` table).
/// - [TransitionCoordinator]: drives the crossfade fade-out/fade-in
///   envelope from the transition config (gapless = no envelope, the
///   queue advances on completion immediately).
///
/// Both take their collaborators as plain functions/streams (no Riverpod
/// `Ref`), which keeps them directly unit-testable. Every failure degrades
/// silently: a broken coordinator must never break playback (same law as
/// the parental hook).
library;

import 'dart:async';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';
import 'package:wavely/playback/transitions/transition_planner.dart';

/// Base engine volume before ReplayGain (the app never drives a user
/// volume slider today; hooks exist if one appears).
const double kBasePlaybackVolume = 1.0;

/// Everything the ReplayGain coordinator needs per track change.
class ReplayGainInputs {
  const ReplayGainInputs({
    required this.mode,
    this.trackGainDb,
    this.albumGainDb,
    this.peakLinear,
    this.preampDb = kDefaultPreampDb,
  });

  final ReplayGainMode mode;
  final double? trackGainDb;
  final double? albumGainDb;
  final double? peakLinear;
  final double preampDb;
}

/// Applies ReplayGain on track change.
class ReplayGainPlaybackCoordinator {
  ReplayGainPlaybackCoordinator({
    required Stream<QueueState> queueStream,
    required Future<ReplayGainInputs> Function(Track track) resolveInputs,
    required Future<void> Function(double volume) setVolume,
  })  : _resolveInputs = resolveInputs,
        _setVolume = setVolume {
    _sub = queueStream.listen(_onQueue);
  }

  final Future<ReplayGainInputs> Function(Track track) _resolveInputs;
  final Future<void> Function(double volume) _setVolume;
  StreamSubscription<QueueState>? _sub;
  String? _lastTrackKey;

  /// Latest volume the coordinator pushed (test seam).
  double? lastVolume;

  void _onQueue(QueueState queue) {
    final Track? track = queue.currentTrack;
    final String? key = track == null
        ? null
        : '${track.sourceTrackId}|${track.filePath ?? ''}';
    if (key == _lastTrackKey) {
      return;
    }
    _lastTrackKey = key;
    unawaited(_applyFor(track));
  }

  Future<void> _applyFor(Track? track) async {
    try {
      if (track == null) {
        await _push(kBasePlaybackVolume);
        return;
      }
      final ReplayGainInputs inputs = await _resolveInputs(track);
      final double multiplier = replayGainMultiplier(
        mode: inputs.mode,
        trackGainDb: inputs.trackGainDb,
        albumGainDb: inputs.albumGainDb,
        peakLinear: inputs.peakLinear,
        preampDb: inputs.preampDb,
      );
      await _push(
        (kBasePlaybackVolume * multiplier).clamp(0.0, 1.0).toDouble(),
      );
    } on Object {
      // Volume application must never break playback.
      try {
        await _push(kBasePlaybackVolume);
      } on Object {
        // Still swallow: coordinator law.
      }
    }
  }

  Future<void> _push(double volume) async {
    lastVolume = volume;
    await _setVolume(volume);
  }

  Future<void> dispose() => _sub?.cancel() ?? Future<void>.value();
}

/// Drives the crossfade fade-out/fade-in envelope.
class TransitionCoordinator {
  TransitionCoordinator({
    required Stream<QueueState> queueStream,
    required TransitionConfig Function() readConfig,
    required Future<void> Function(double volume) setVolume,
  })  : _readConfig = readConfig,
        _setVolume = setVolume {
    _sub = queueStream.listen(_observe);
  }

  final TransitionConfig Function() _readConfig;
  final Future<void> Function(double volume) _setVolume;
  StreamSubscription<QueueState>? _sub;

  /// Queue index the envelope is currently tracking.
  int _observedIndex = -1;
  bool _fadeOutActive = false;
  bool _fadeInActive = false;

  /// Latest volume the coordinator pushed (test seam).
  double? lastVolume;

  void _observe(QueueState queue) {
    final Track? current = queue.currentTrack;
    if (current == null) {
      return;
    }
    if (queue.currentIndex != _observedIndex) {
      // New track: open the fade-in window, reset fade-out bookkeeping.
      _observedIndex = queue.currentIndex;
      _fadeOutActive = false;
      _fadeInActive = true;
      return;
    }
    final TransitionConfig config;
    try {
      config = _readConfig();
    } on Object {
      return;
    }
    if (!config.crossfadeEnabled) {
      // Gapless (or plain) playback: full volume, no envelope.
      if (_fadeInActive || _fadeOutActive) {
        _fadeInActive = false;
        _fadeOutActive = false;
        unawaited(_push(1.0));
      }
      return;
    }

    final TransitionDecision decision = planTransition(
      config: config,
      position: queue.position,
      duration: queue.duration == Duration.zero
          ? Duration(milliseconds: current.durationMs)
          : queue.duration,
      trackJustStarted: _fadeInActive,
    );
    switch (decision) {
      case TransitionFadeOut(:final double volumeFactor):
        _fadeOutActive = true;
        _fadeInActive = false;
        unawaited(_push(volumeFactor));
      case TransitionFadeIn(:final double volumeFactor):
        unawaited(_push(volumeFactor));
        if (queue.position >=
            Duration(seconds: config.crossfadeSeconds)) {
          _fadeInActive = false;
          unawaited(_push(1.0));
        }
      case TransitionNone():
        break;
    }
  }

  Future<void> _push(double factor) async {
    lastVolume =
        (kBasePlaybackVolume * factor).clamp(0.0, 1.0).toDouble();
    try {
      await _setVolume(lastVolume!);
    } on Object {
      // Never break playback.
    }
  }

  Future<void> dispose() => _sub?.cancel() ?? Future<void>.value();
}

/// Wiring helper for the composition root: builds the queue stream from
/// the QueueManager notifier.
Stream<QueueState> queueStateStreamOf(QueueManager manager) =>
    manager.stream;
