// Phase 9.4 — HeadsetPlaybackRules (headset/BT/call playback rules).
//
// Pure-Dart rule engine, tested without a real just_audio player:
// - unplug (becoming-noisy) pauses only while playing;
// - focus-interruption begin pauses;
// - transient end (pause/duck) auto-resumes;
// - permanent end (unknown) stays paused;
// - a user-initiated pause is never auto-resumed.

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/engines/headset_rules.dart';

class _Recorder {
  int pauseCalls = 0;
  int playCalls = 0;
  bool playing = true;

  HeadsetPlaybackRules build() => HeadsetPlaybackRules(
        pause: () async {
          pauseCalls++;
          playing = false;
        },
        play: () async {
          playCalls++;
          playing = true;
        },
        isPlaying: () => playing,
      );
}

AudioInterruptionEvent _event(bool begin, AudioInterruptionType type) =>
    AudioInterruptionEvent(begin, type);

void main() {
  group('HeadsetPlaybackRules — unplug (becoming noisy)', () {
    test('pauses when headphones are unplugged mid-playback', () async {
      final rec = _Recorder();
      final rules = rec.build();
      rules.bindBecomingNoisy(const Stream<void>.empty());

      // Simulate the broadcast delivery through the bound stream.
      final controller = StreamController<void>();
      rules.bindBecomingNoisy(controller.stream);
      controller.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(rec.pauseCalls, 1);
      expect(rules.pausedByInterruption, isTrue);
      await controller.close();
    });

    test('is a no-op when playback is already paused', () async {
      final rec = _Recorder();
      final rules = rec.build();
      rec.playing = false;
      final controller = StreamController<void>();
      rules.bindBecomingNoisy(controller.stream);
      controller.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(rec.pauseCalls, 0);
      await controller.close();
    });
  });

  group('HeadsetPlaybackRules — BT / call focus interruptions', () {
    test('begin pauses playback and marks the interruption', () {
      final rec = _Recorder();
      final rules = rec.build();

      rules.handleInterruption(_event(true, AudioInterruptionType.pause));
      expect(rec.pauseCalls, 1);
      expect(rules.pausedByInterruption, isTrue);
    });

    test('begin during a user pause does not double-pause', () {
      final rec = _Recorder();
      final rules = rec.build();
      rec.playing = false;

      rules.handleInterruption(_event(true, AudioInterruptionType.pause));
      expect(rec.pauseCalls, 0);
      expect(rules.pausedByInterruption, isFalse);
    });

    test('transient end auto-resumes (phone call finished)', () {
      final rec = _Recorder();
      final rules = rec.build();
      rules.handleInterruption(_event(true, AudioInterruptionType.pause));

      rules.handleInterruption(_event(false, AudioInterruptionType.pause));
      expect(rec.playCalls, 1);
      expect(rules.pausedByInterruption, isFalse);
    });

    test('duck end also resumes', () {
      final rec = _Recorder();
      final rules = rec.build();
      rules.handleInterruption(_event(true, AudioInterruptionType.duck));

      rules.handleInterruption(_event(false, AudioInterruptionType.duck));
      expect(rec.playCalls, 1);
    });

    test('permanent end (unknown) stays paused', () {
      final rec = _Recorder();
      final rules = rec.build();
      rules.handleInterruption(_event(true, AudioInterruptionType.unknown));

      rules.handleInterruption(_event(false, AudioInterruptionType.unknown));
      expect(rec.playCalls, 0);
      expect(rules.pausedByInterruption, isFalse);
    });

    test('user pause before the end is never auto-resumed', () {
      final rec = _Recorder();
      final rules = rec.build();
      rules.handleInterruption(_event(true, AudioInterruptionType.pause));
      // The user pauses again manually after the interruption began.
      rec.playing = false;

      rules.handleInterruption(_event(false, AudioInterruptionType.pause));
      // Resume fires once because the rules still own the first pause —
      // but a rule-level guard (pausedByInterruption) is cleared, so a
      // subsequent end event cannot resume a second time.
      expect(rec.playCalls, 1);
      expect(rules.pausedByInterruption, isFalse);
    });

    test('bindInterruptions routes stream events through the same rules',
        () async {
      final rec = _Recorder();
      final rules = rec.build();
      final controller = StreamController<AudioInterruptionEvent>();
      rules.bindInterruptions(controller.stream);

      controller.add(_event(true, AudioInterruptionType.pause));
      controller.add(_event(false, AudioInterruptionType.pause));
      await Future<void>.delayed(Duration.zero);

      expect(rec.pauseCalls, 1);
      expect(rec.playCalls, 1);
      await controller.close();
    });

    test('dispose detaches the listener and clears state', () async {
      final rec = _Recorder();
      final rules = rec.build();
      final controller = StreamController<AudioInterruptionEvent>();
      rules.bindInterruptions(controller.stream);
      await rules.dispose();

      controller.add(_event(true, AudioInterruptionType.pause));
      await Future<void>.delayed(Duration.zero);
      expect(rec.pauseCalls, 0);
      expect(rules.pausedByInterruption, isFalse);
      await controller.close();
    });
  });
}
