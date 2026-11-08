import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// Phase 9 headset / Bluetooth playback rules (Musicolet parity).
///
/// Pure-Dart rule engine so the behaviour is unit-testable without a real
/// just_audio player:
///
/// 1. **Unplug pause** — a `becoming-noisy` broadcast (wired headset or
///    A2DP headphones) pauses playback immediately.
/// 2. **BT / call rules** — audio-focus interruptions: a *transient* loss
///    (phone call, navigation prompt) pauses; when the interruption ends
///    with `AudioInterruptionType.pause`/`duck`, playback auto-resumes; a
///    `unknown` (permanent) loss keeps playback paused.
///
/// The mobile engine binds the real streams (`player.becomingNoisyEventStream`
/// and `session.interruptionEventStream`); desktop / web / tests never bind
/// anything and the class stays inert.
class HeadsetPlaybackRules {
  /// Creates the rules with the playback actions to invoke.
  HeadsetPlaybackRules({
    required Future<void> Function() pause,
    required Future<void> Function() play,
    required bool Function() isPlaying,
  })  : _pause = pause,
        _play = play,
        _isPlaying = isPlaying;

  final Future<void> Function() _pause;
  final Future<void> Function() _play;
  final bool Function() _isPlaying;

  /// Whether the engine is currently paused because of an interruption.
  /// Governs auto-resume so a user-initiated pause is never overridden.
  bool pausedByInterruption = false;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// Binds the becoming-noisy stream (headset unplug / BT disconnect).
  ///
  /// just_audio exposes `AudioPlayer.becomingNoisyEventStream` — a broadcast
  /// of the ACTION_AUDIO_BECOMING_NOISY intent, which Android fires when
  /// headphones are unplugged or a Bluetooth headset disconnects.
  void bindBecomingNoisy(Stream<void> events) {
    events.listen((_) {
      if (!_isPlaying()) {
        return;
      }
      pausedByInterruption = true;
      _pause();
    });
  }

  /// Binds the audio-focus interruption stream (BT / call rules).
  ///
  /// - begin + pause/duck/unknown: pause (remember the pause).
  /// - end + pause: transient loss over — auto-resume.
  /// - end + duck: ducking over — auto-resume.
  /// - end + unknown: permanent loss — stay paused.
  void bindInterruptions(Stream<AudioInterruptionEvent> events) {
    _interruptionSub = events.listen(handleInterruption);
  }

  /// Processes one interruption event (public so engines that own the
  /// subscription themselves can route events in).
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.duck:
        case AudioInterruptionType.unknown:
          if (_isPlaying()) {
            pausedByInterruption = true;
            _pause();
          }
      }
      return;
    }
    // Interruption ended.
    switch (event.type) {
      case AudioInterruptionType.pause:
      case AudioInterruptionType.duck:
        if (pausedByInterruption) {
          pausedByInterruption = false;
          _play();
        }
      case AudioInterruptionType.unknown:
        // Permanent focus loss — stay paused until the user presses play.
        pausedByInterruption = false;
    }
  }

  /// Detaches the interruption listener (engine dispose).
  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    pausedByInterruption = false;
  }
}
