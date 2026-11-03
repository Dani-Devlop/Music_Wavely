/// Stage 4: EqualizerController — engine push + per-device preset storage
/// over a real in-memory Drift database and the scriptable engine fake.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_controller.dart';

import '../../support/fake_playback_engine.dart';

void main() {
  late AppDatabase db;
  late FakePlaybackEngine engine;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    engine = FakePlaybackEngine();
  });
  tearDown(() => db.close());

  EqualizerController buildController({String deviceId = 'dev-1'}) =>
      EqualizerController(db: db, deviceId: deviceId, engine: engine);

  group('engine capability plumbing', () {
    test('exposes the engine EQ when the engine implements the interface',
        () {
      final EqualizerController controller = buildController();
      expect(controller.engineEq, same(engine));
    });

    test('engineEq is null for a non-capable engine', () {
      final EqualizerController controller = EqualizerController(
        db: db,
        deviceId: 'dev-1',
        engine: _PlainEngine(),
      );
      expect(controller.engineEq, isNull);
      expect(controller.canApplyGains, completion(isFalse));
    });

    test('canApplyGains is false when the fake reports no EQ', () async {
      engine.eqAvailable = false;
      final EqualizerController controller = buildController();
      expect(await controller.canApplyGains, isFalse);
    });

    test('applyGains clamps and pushes every band', () async {
      final EqualizerController controller = buildController();
      final bool ok = await controller.applyGains(
        <double>[-99, 5, 0, 0, 99],
      );
      expect(ok, isTrue);
      expect(engine.eqGains, <double>[kEqMinGainDb, 5, 0, 0, kEqMaxGainDb]);
      expect(engine.setEqualizerBandGainCalls, 5);
    });

    test('applyGains resamples the 10-band layout to the engine band count',
        () async {
      engine.eqBandCount = 3;
      final EqualizerController controller = buildController();
      final bool ok = await controller.applyGains(
        List<double>.generate(10, (int i) => i.toDouble()),
      );
      expect(ok, isTrue);
      expect(engine.eqGains, hasLength(3));
    });

    test('applyGains is false when the engine refuses', () async {
      engine.eqAvailable = false;
      final EqualizerController controller = buildController();
      expect(await controller.applyGains(const <double>[1, 2, 3]), isFalse);
    });

    test('setEnabled forwards to the engine', () async {
      final EqualizerController controller = buildController();
      expect(await controller.setEnabled(enabled: false), isTrue);
      expect(engine.lastEqualizerEnabled, isFalse);
    });
  });

  group('builtin presets', () {
    test('catalogue is exposed and lookup works', () {
      final EqualizerController controller = buildController();
      expect(controller.builtinPresets, same(kBuiltinEqPresets));
      expect(controller.builtinByName('Rock'), isNotNull);
      expect(controller.builtinByName('Nope'), isNull);
    });

    test('applyPreset(builtin:...) applies the gains', () async {
      final EqualizerController controller = buildController();
      final List<double>? applied =
          await controller.applyPreset('builtin:Bass Boost');
      expect(applied, isNotNull);
      expect(engine.eqGains.first, 6.0);
    });

    test('applyPreset returns null for an unknown preset', () async {
      final EqualizerController controller = buildController();
      expect(await controller.applyPreset('builtin:Nope'), isNull);
      expect(await controller.applyPreset('Nope'), isNull);
    });
  });

  group('user presets (per device)', () {
    test('save + apply roundtrip', () async {
      final EqualizerController controller = buildController();
      await controller.savePreset('My Curve', const <double>[3, 2, 1]);
      final List<double>? applied =
          await controller.applyPreset('My Curve');
      expect(applied, isNotNull);
      expect(engine.eqGains.take(3), <double>[3, 2, 1]);
    });

    test('presets are scoped per device', () async {
      await buildController(deviceId: 'dev-1')
          .savePreset('Only Mine', const <double>[1, 1, 1, 1, 1]);
      final EqualizerController other = buildController(deviceId: 'dev-2');
      expect(await other.userPresets(), isEmpty);
      expect(await other.applyPreset('Only Mine'), isNull);
      expect((await buildController(deviceId: 'dev-1').userPresets()),
          hasLength(1));
    });

    test('userPresets lists saved rows', () async {
      final EqualizerController controller = buildController();
      await controller.savePreset('B', const <double>[1]);
      await controller.savePreset('A', const <double>[2]);
      final List<String> names =
          (await controller.userPresets()).map((row) => row.name).toList();
      expect(names, <String>['A', 'B']);
    });

    test('deletePreset removes the device-scoped row', () async {
      final EqualizerController controller = buildController();
      await controller.savePreset('Temp', const <double>[1]);
      expect(await controller.deletePreset('Temp'), 1);
      expect(await controller.deletePreset('Temp'), 0);
    });

    test('saving the same name overwrites (device scoped)', () async {
      final EqualizerController controller = buildController();
      await controller.savePreset('Same', const <double>[1]);
      await controller.savePreset('Same', const <double>[2, 2]);
      expect(await controller.userPresets(), hasLength(1));
      expect(
        (await controller.applyPreset('Same'))!.take(2),
        <double>[2, 2],
      );
    });
  });
}

/// Minimal engine WITHOUT the equalizer capability (the exact situation of
/// the web engine and of every pre-Stage-4 engine).
class _PlainEngine implements PlaybackEngine {
  @override
  Future<void> load(Track t, {Duration? startAt}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration p) async {}

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<PlaybackState> get stateStream =>
      const Stream<PlaybackState>.empty();

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
