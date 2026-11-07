/// Tests for the Phase 8.3 transition planner + config codec.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/transitions/transition_planner.dart';

void main() {
  group('TransitionConfig', () {
    test('sanitize clamps the crossfade into 0..30', () {
      expect(
        TransitionConfig.sanitize(crossfadeSeconds: 99, gapless: true)
            .crossfadeSeconds,
        30,
      );
      expect(
        TransitionConfig.sanitize(crossfadeSeconds: -5, gapless: true)
            .crossfadeSeconds,
        0,
      );
      expect(
        TransitionConfig.sanitize(crossfadeSeconds: 12, gapless: false)
            .gapless,
        isFalse,
      );
    });

    test('json roundtrip', () {
      const TransitionConfig config = TransitionConfig(
        crossfadeSeconds: 8,
        gapless: false,
      );
      final TransitionConfig restored =
          TransitionConfig.fromJson(config.toJson());
      expect(restored.crossfadeSeconds, 8);
      expect(restored.gapless, isFalse);
    });

    test('corrupt json degrades to defaults', () {
      final TransitionConfig restored = TransitionConfig.fromJson(
        <String, Object?>{'crossfadeSeconds': 'eight', 'gapless': 'yes'},
      );
      expect(restored.crossfadeSeconds, 0);
      expect(restored.gapless, isTrue);
    });
  });

  group('fadeCurve', () {
    test('is an equal-power curve (0 → 0, 1 → 1, midpoint 0.707)', () {
      expect(fadeCurve(0), closeTo(0, 0.0001));
      expect(fadeCurve(1), closeTo(1, 0.0001));
      expect(fadeCurve(0.5), closeTo(0.7071, 0.001));
      expect(fadeCurve(0.25), closeTo(0.3827, 0.001));
    });

    test('clamps out-of-range inputs', () {
      expect(fadeCurve(-1), 0);
      expect(fadeCurve(2), 1);
    });
  });

  group('planTransition', () {
    final Duration trackLength = const Duration(minutes: 3);

    test('crossfade off → none everywhere', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 0);
      expect(
        planTransition(
          config: config,
          position: trackLength - const Duration(seconds: 1),
          duration: trackLength,
          trackJustStarted: false,
        ),
        isA<TransitionNone>(),
      );
    });

    test('fade-out starts when the remaining time enters the window', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 6);
      final TransitionDecision inside = planTransition(
        config: config,
        position: trackLength - const Duration(seconds: 3),
        duration: trackLength,
        trackJustStarted: false,
      );
      expect(inside, isA<TransitionFadeOut>());
      // Halfway through the window → ~0.5 linear → equal-power ~0.707.
      final TransitionFadeOut fadeOut = inside as TransitionFadeOut;
      expect(fadeOut.volumeFactor, closeTo(0.7071, 0.01));
    });

    test('fade-out deepens towards the very end', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 6);
      final TransitionDecision atEnd = planTransition(
        config: config,
        position: trackLength - const Duration(milliseconds: 100),
        duration: trackLength,
        trackJustStarted: false,
      );
      final TransitionFadeOut fadeOut = atEnd as TransitionFadeOut;
      expect(fadeOut.volumeFactor, lessThan(0.1));
    });

    test('no fade-out before the window', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 6);
      expect(
        planTransition(
          config: config,
          position: const Duration(minutes: 1),
          duration: trackLength,
          trackJustStarted: false,
        ),
        isA<TransitionNone>(),
      );
    });

    test('fade-in applies at the head of a fresh track', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 6);
      final TransitionDecision head = planTransition(
        config: config,
        position: const Duration(seconds: 3),
        duration: trackLength,
        trackJustStarted: true,
      );
      expect(head, isA<TransitionFadeIn>());
      final TransitionFadeIn fadeIn = head as TransitionFadeIn;
      expect(fadeIn.volumeFactor, closeTo(0.7071, 0.01));
    });

    test('unknown duration (live streams) never fades out', () {
      const TransitionConfig config = TransitionConfig(crossfadeSeconds: 6);
      expect(
        planTransition(
          config: config,
          position: const Duration(minutes: 2),
          duration: Duration.zero,
          trackJustStarted: false,
        ),
        isA<TransitionNone>(),
      );
    });

    test('gapless with crossfade off is a no-op plan (immediate advance)',
        () {
      const TransitionConfig config = TransitionConfig(
        crossfadeSeconds: 0,
        gapless: true,
      );
      expect(
        planTransition(
          config: config,
          position: trackLength,
          duration: trackLength,
          trackJustStarted: false,
        ),
        isA<TransitionNone>(),
      );
    });
  });
}
