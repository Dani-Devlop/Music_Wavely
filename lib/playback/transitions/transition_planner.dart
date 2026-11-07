/// Crossfade / gapless transition planning (Phase 8.3) — pure logic.
///
/// The engines are single-track loaders, so crossfade is realized as a
/// fade-out over the last `crossfade` seconds of the outgoing track and a
/// fade-in over the first `crossfade` seconds of the incoming one (the
/// audio overlap a two-decoder engine would produce is approximated by
/// the volume envelope; see the parity report note). Gapless means "no
/// fade and no coordinator delay": the queue advances on completion
/// immediately, which is the engine's existing behavior.
library;

import 'dart:math' as math;

/// Persisted transition configuration.
class TransitionConfig {
  const TransitionConfig({
    this.crossfadeSeconds = 0,
    this.gapless = true,
  }) : assert(crossfadeSeconds >= 0 && crossfadeSeconds <= 30);

  /// Crossfade duration 0..30 s (0 = off).
  final int crossfadeSeconds;

  /// Gapless playback preference.
  final bool gapless;

  bool get crossfadeEnabled => crossfadeSeconds > 0;

  TransitionConfig copyWith({int? crossfadeSeconds, bool? gapless}) =>
      TransitionConfig(
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        gapless: gapless ?? this.gapless,
      );

  static const int kMaxCrossfadeSeconds = 30;

  /// Clamps and builds; invalid inputs degrade to sane values.
  factory TransitionConfig.sanitize({
    required int crossfadeSeconds,
    required bool gapless,
  }) =>
      TransitionConfig(
        crossfadeSeconds:
            crossfadeSeconds.clamp(0, kMaxCrossfadeSeconds),
        gapless: gapless,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'crossfadeSeconds': crossfadeSeconds,
        'gapless': gapless,
      };

  factory TransitionConfig.fromJson(Map<String, Object?> json) =>
      TransitionConfig.sanitize(
        crossfadeSeconds: json['crossfadeSeconds'] is int
            ? json['crossfadeSeconds']! as int
            : 0,
        gapless: json['gapless'] is bool ? json['gapless']! as bool : true,
      );
}

/// What the coordinator should do at a given playback moment.
sealed class TransitionDecision {
  const TransitionDecision();
}

/// Nothing to do right now.
class TransitionNone extends TransitionDecision {
  const TransitionNone();
}

/// Begin (or continue) the fade-out window.
class TransitionFadeOut extends TransitionDecision {
  const TransitionFadeOut({required this.volumeFactor});

  /// Volume multiplier 0..1 for the current position.
  final double volumeFactor;
}

/// Fade-in over the head of a freshly started track.
class TransitionFadeIn extends TransitionDecision {
  const TransitionFadeIn({required this.volumeFactor});

  final double volumeFactor;
}

/// Linear fade curve with a smooth floor/ceiling: position `t` in the
/// window (0..1) → volume factor. Equal-power (constant-loudness) fade —
/// the crossfade standard.
double fadeCurve(double t) {
  final double clamped = t.clamp(0.0, 1.0);
  return math.sin((math.pi / 2) * clamped);
}

/// Plans the transition decision for one tick.
///
/// - Crossfade enabled + remaining <= window → [TransitionFadeOut] with
///   the decreasing factor.
/// - Crossfade enabled + elapsed <= window at the head of a track →
///   [TransitionFadeIn] with the increasing factor.
/// - Gapless with crossfade off → [TransitionNone] (engine advances on
///   completion immediately; nothing to fade).
TransitionDecision planTransition({
  required TransitionConfig config,
  required Duration position,
  required Duration duration,
  required bool trackJustStarted,
}) {
  if (!config.crossfadeEnabled || duration <= Duration.zero) {
    return const TransitionNone();
  }
  final Duration window =
      Duration(seconds: config.crossfadeSeconds);
  final Duration remaining = duration - position;
  final Duration windowMs = Duration(milliseconds: window.inMilliseconds);

  if (remaining <= window && remaining > Duration.zero) {
    // Fade-out: 1.0 at window start → 0.0 at the very end.
    final double t = remaining.inMilliseconds / windowMs.inMilliseconds;
    // Linear-down mapped through the equal-power curve for the tail.
    final double factor = fadeCurve(t);
    return TransitionFadeOut(volumeFactor: factor);
  }
  if (trackJustStarted && position < windowMs) {
    final double t = position.inMilliseconds / windowMs.inMilliseconds;
    return TransitionFadeIn(volumeFactor: fadeCurve(t));
  }
  return const TransitionNone();
}
