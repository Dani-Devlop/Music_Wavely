// Stage 5 cross-feature regression — Scenario 2: EQ/Hi-Res × Playback
// Engine.
//
// Verifies that applying an EQ preset (built-in or persisted per-device
// user preset) or requesting Hi-Res exclusive mode does NOT disturb the
// engine's transport contract: the position stream keeps flowing, seek
// keeps working, state transitions keep arriving and play/pause stay
// responsive — the "a broken EQ must never break playback" guarantee, now
// proven across the feature boundary.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_controller.dart';
import 'package:wavely/playback/hires/hires_audio.dart';

import '../support/fake_playback_engine.dart';
import '../support/track_factory.dart';

/// A minimal engine WITHOUT the [EqualizerControl] capability — proves the
/// controller degrades safely on legacy engines.
class _PlainEngine extends PlaybackEngine {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast(sync: true);

  int seekCalls = 0;
  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> load(Track t, {Duration? startAt}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration p) async {
    seekCalls++;
    seeks.add(p);
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _states.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('EQ preset → engine health', () {
    test('applying a built-in preset keeps position/seek/state alive',
        () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final EqualizerController controller = EqualizerController(
        db: db,
        deviceId: 'device-a',
        engine: engine,
      );

      final List<Duration> positions = <Duration>[];
      final List<PlaybackState> states = <PlaybackState>[];
      engine.positionStream.listen(positions.add);
      engine.stateStream.listen(states.add);

      // Engine is playing before the EQ touches it.
      engine.emitState(PlaybackState.playing);
      engine.emitPosition(const Duration(seconds: 1));

      final List<double>? applied =
          await controller.applyPreset('builtin:Rock');
      expect(applied, kBuiltinEqPresets
          .firstWhere((p) => p.name == 'Rock')
          .gainsDb);
      // 10-band preset resampled onto the fake engine's 5 bands, all bands
      // accepted.
      expect(engine.setEqualizerBandGainCalls, 5);
      expect(engine.eqGains, isNotNull);

      // Transport contract intact AFTER the EQ push:
      engine.emitPosition(const Duration(seconds: 2));
      engine.emitPosition(const Duration(seconds: 3));
      await engine.seek(const Duration(seconds: 30));
      engine.emitState(PlaybackState.paused);
      await engine.play();

      expect(positions, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      ]);
      expect(engine.seeks.last, const Duration(seconds: 30));
      expect(states, <PlaybackState>[
        PlaybackState.playing,
        PlaybackState.paused,
      ]);
      expect(engine.playCalls, 1);
      expect(engine.disposed, isFalse);
      expect(await controller.canApplyGains, isTrue);
    });

    test('user preset saved per device applies + engine stays healthy; '
        'other devices do not see it', () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final EqualizerController controller = EqualizerController(
        db: db,
        deviceId: 'device-a',
        engine: engine,
      );

      await controller.savePreset(
        'Night Curve',
        <double>[10, -10, 10, -10, 10, -10, 10, -10, 10, -10],
      );

      // Per-device scoping (Drift eq_presets).
      final List<dynamic> otherDevice =
          await db.eqPresetsDao.forDevice('device-b');
      expect(otherDevice, isEmpty);
      expect((await controller.userPresets()).single.name, 'Night Curve');

      final List<double>? gains = await controller.applyPreset('Night Curve');
      expect(gains, isNotNull);
      expect(gains!.length, 10);
      // Engine received the clamped + resampled vector. The 10-band
      // alternating curve resamples onto 5 bands via nearest-standard-band
      // mapping: indices 0/2/5/7/9 map to [10, 10, -10, -10, -10].
      expect(engine.eqGains.length, 5);
      expect(engine.eqGains, <double>[10, 10, 10, -10, -10]);

      // Engine still healthy after the user-preset push.
      final List<Duration> positions = <Duration>[];
      engine.positionStream.listen(positions.add);
      engine.emitPosition(const Duration(seconds: 9));
      expect(positions, <Duration>[const Duration(seconds: 9)]);
      await engine.seek(const Duration(minutes: 1));
      expect(engine.seeks.last, const Duration(minutes: 1));

      // Delete → unknown preset → null, engine untouched.
      expect(await controller.deletePreset('Night Curve'), 1);
      expect(await controller.applyPreset('Night Curve'), isNull);
      expect(engine.eqGains[0], 10.0,
          reason: 'a failed lookup must not push anything to the engine');
    });

    test('engine without EQ capability degrades without breaking playback',
        () async {
      final FakePlaybackEngine engine = FakePlaybackEngine()
        ..eqAvailable = false;
      final EqualizerController controller = EqualizerController(
        db: db,
        deviceId: 'device-a',
        engine: engine,
      );

      expect(await controller.canApplyGains, isFalse);
      expect(await controller.setEnabled(enabled: true), isFalse);
      expect(await controller.applyGains(<double>[1, 2, 3]), isFalse);

      // Playback fully functional.
      final List<PlaybackState> states = <PlaybackState>[];
      engine.stateStream.listen(states.add);
      engine.emitState(PlaybackState.playing);
      await engine.seek(const Duration(seconds: 12));
      expect(states, <PlaybackState>[PlaybackState.playing]);
      expect(engine.seeks.single, const Duration(seconds: 12));
    });

    test('plain engine (no EqualizerControl) is never touched', () async {
      final _PlainEngine engine = _PlainEngine();
      final EqualizerController controller = EqualizerController(
        db: db,
        deviceId: 'device-a',
        engine: engine,
      );

      expect(controller.engineEq, isNull);
      expect(await controller.queryEngine(), isNull);
      expect(await controller.setEnabled(enabled: true), isFalse);
      expect(await controller.applyGains(<double>[3, 3]), isFalse);

      // And the engine keeps working as a pure PlaybackEngine.
      final List<Duration> positions = <Duration>[];
      engine.positionStream.listen(positions.add);
      engine.seek(const Duration(seconds: 5));
      expect(engine.seekCalls, 1);
      // (position emission is engine-driven in production; the fake's
      // controller is only closed on dispose)
      await engine.dispose();
      expect(positions, isEmpty);
    });
  });

  group('Hi-Res exclusive mode → engine health', () {
    test('granted exclusive mode does not disturb the transport contract',
        () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final HiResAudioController hires = HiResAudioController(
        activator: () async => true,
        sdkIntProvider: () async => 34,
      );

      final List<Duration> positions = <Duration>[];
      engine.positionStream.listen(positions.add);
      engine.emitState(PlaybackState.playing);

      final HiResRequestResult result =
          await hires.enableAndroidExclusiveMode();
      expect(result.granted, isTrue);
      expect(result.reason, contains('granted'));

      // Playback keeps flowing exactly as before (background playback is
      // engine-owned; the request must not stop or dispose it).
      engine.emitPosition(const Duration(seconds: 1));
      engine.emitPosition(const Duration(seconds: 2));
      await engine.seek(const Duration(seconds: 45));
      engine.emitState(PlaybackState.paused);
      await engine.play();

      expect(positions, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(engine.seeks.single, const Duration(seconds: 45));
      expect(engine.disposed, isFalse);
      expect(engine.pauseCalls, 1);
      expect(engine.playCalls, 1,
          reason: 'transport commands still reach the engine after the '
              'exclusive-mode request');
    });

    test('refused / missing native handler degrades cleanly', () async {
      final HiResAudioController refused = HiResAudioController(
        activator: () async => false,
        sdkIntProvider: () async => 34,
      );
      final HiResRequestResult r1 = await refused.enableAndroidExclusiveMode();
      expect(r1.granted, isFalse);
      expect(r1.reason, contains('refused'));

      // Documented stub state: the platform channel throws
      // MissingPluginException until the owner adds the Kotlin handler.
      final HiResAudioController missing = HiResAudioController(
        activator: () async =>
            throw MissingPluginException('no native handler'),
        sdkIntProvider: () async => 35,
      );
      final HiResRequestResult r2 = await missing.enableAndroidExclusiveMode();
      expect(r2.granted, isFalse);
      expect(r2.reason, contains('Exclusive-mode request failed'));

      // Below the Android 14 gate the channel is never asked.
      var asked = false;
      final HiResAudioController old = HiResAudioController(
        activator: () async {
          asked = true;
          return true;
        },
        sdkIntProvider: () async => 33,
      );
      final HiResRequestResult r3 = await old.enableAndroidExclusiveMode();
      expect(r3.granted, isFalse);
      expect(asked, isFalse);
      expect(HiResAudioPolicy.androidExclusiveSupported(34), isTrue);
      expect(HiResAudioPolicy.androidExclusiveSupported(null), isFalse);
    });
  });

  group('EQ + Hi-Res combined on one engine', () {
    test('both feature pushes on the same engine stay mutually harmless',
        () async {
      final FakePlaybackEngine engine = FakePlaybackEngine();
      final EqualizerController eq = EqualizerController(
        db: db,
        deviceId: 'device-a',
        engine: engine,
      );
      final HiResAudioController hires = HiResAudioController(
        activator: () async => true,
        sdkIntProvider: () async => 34,
      );

      final List<Duration> positions = <Duration>[];
      final List<PlaybackState> states = <PlaybackState>[];
      engine.positionStream.listen(positions.add);
      engine.stateStream.listen(states.add);

      // Interleave the two DAP features around real transport traffic —
      // the exact sequence a "DAP mode" session produces.
      await eq.applyPreset('builtin:Bass Boost');
      expect(await hires.enableAndroidExclusiveMode(), isNotNull);
      engine.emitState(PlaybackState.playing);
      engine.emitPosition(const Duration(seconds: 1));
      await engine.seek(const Duration(seconds: 20));
      expect(await eq.applyPreset('builtin:Flat'), isNotNull);
      engine.emitPosition(const Duration(seconds: 2));
      await hires.enableAndroidExclusiveMode();
      engine.emitState(PlaybackState.paused);
      await engine.pause();

      // Every event from both features arrived, in order, nothing dropped.
      expect(positions, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(states, <PlaybackState>[
        PlaybackState.playing,
        PlaybackState.paused,
      ]);
      expect(engine.seeks.single, const Duration(seconds: 20));
      expect(engine.pauseCalls, 1);
      expect(engine.setEqualizerBandGainCalls, 10,
          reason: 'two presets × 5 bands each');
      // Flat pushed zeroes after Bass Boost's shaped curve.
      expect(engine.eqGains.every((double g) => g == 0), isTrue);
    });
  });
}
