/// Tests for the Phase 8.4 per-device audio profile store + controller
/// (in-memory Drift, scripted output-device tracker, fake engine).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/audio_profiles_dao.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/effects/audio_effects.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/equalizer/equalizer_control.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';
import 'package:wavely/playback/profiles/audio_profile_codec.dart';
import 'package:wavely/playback/profiles/output_device_tracker.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';

/// Scriptable output device tracker.
class FakeOutputDeviceTracker implements OutputDeviceTracker {
  FakeOutputDeviceTracker(String initial) : _current = initial;

  final StreamController<String> _changes =
      StreamController<String>.broadcast();
  String _current;
  final Map<String, String> labels = <String, String>{};

  String get current => _current;

  @override
  Future<String> currentOutputDeviceId() async => _current;

  @override
  Stream<String> get deviceChanges => _changes.stream;

  @override
  Future<String> deviceLabel(String deviceId) async =>
      labels[deviceId] ?? deviceId;

  void switchTo(String deviceId) {
    _current = deviceId;
    _changes.add(deviceId);
  }

  void close() => _changes.close();
}

/// Fake engine implementing both engine capabilities.
class FakeCapableEngine implements PlaybackEngine, EqualizerControl,
    AudioEffectsControl {
  final List<double> gains = <double>[];
  bool eqEnabled = false;
  AudioEffectsState? appliedEffects;
  final List<double> volumes = <double>[];

  @override
  bool get equalizerAvailable => true;

  @override
  bool get effectsAvailable => true;

  @override
  Future<EqualizerInfo?> queryEqualizer() async => const EqualizerInfo(
        bandCount: 5,
        bandFrequencies: <double>[60, 230, 910, 3600, 14000],
        minGainDb: -12,
        maxGainDb: 12,
      );

  @override
  Future<bool> setEqualizerEnabled({required bool enabled}) async {
    eqEnabled = enabled;
    return true;
  }

  @override
  Future<bool> setEqualizerBandGain(int bandIndex, double gainDb) async {
    while (gains.length <= bandIndex) {
      gains.add(0);
    }
    gains[bandIndex] = gainDb;
    return true;
  }

  @override
  Future<bool> applyEffects(AudioEffectsState state) async {
    appliedEffects = state;
    return true;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

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
  Future<void> dispose() async {}
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('AudioProfileCodec', () {
    test('gains JSON is a fixed 5-slot array', () {
      expect(
        AudioProfileCodec.encodeGains(<double>[1, 2]),
        '[1.0,2.0,0.0,0.0,0.0]',
      );
    });

    test('row ↔ state roundtrip', () async {
      await db.audioProfilesDao.upsert(
        deviceKey: 'dev',
        outputDeviceId: 'wired',
        label: 'Wired',
        values: const AudioProfileValues(
          eqEnabled: false,
          eqGainsJson: '[3.0,-2.0,0.0,1.5,4.0]',
          eqPresetKey: 'builtin:Rock',
          bassBoost: 30,
          virtualizer: 45,
          reverbPreset: 'Plate',
          balance: -0.25,
          forceMono: true,
          replayGainMode: 'track',
          replayGainPreampDb: 1.5,
          crossfadeSeconds: 9,
          gapless: false,
        ),
      );
      final AudioProfileRow row = (await db.audioProfilesDao
          .forDevice('dev'))
          .single;
      final AudioSettingsState state = AudioProfileCodec.fromRow(row);
      expect(state.eqEnabled, isFalse);
      expect(state.eqGains, <double>[3, -2, 0, 1.5, 4]);
      expect(state.eqPresetKey, 'builtin:Rock');
      expect(state.effects.bassBoost, 30);
      expect(state.effects.virtualizer, 45);
      expect(state.effects.reverbPreset, 'Plate');
      expect(state.effects.balance, -0.25);
      expect(state.effects.forceMono, isTrue);
      expect(state.replayGainMode, ReplayGainMode.track);
      expect(state.replayGainPreampDb, 1.5);
      expect(state.crossfadeSeconds, 9);
      expect(state.gapless, isFalse);

      final AudioProfileValues values = AudioProfileCodec.toValues(state);
      expect(values.eqGainsJson, '[3.0,-2.0,0.0,1.5,4.0]');
      expect(values.replayGainMode, 'track');
    });

    test('corrupt gains JSON degrades to an empty vector', () async {
      await db.audioProfilesDao.upsert(
        deviceKey: 'dev',
        outputDeviceId: 'x',
        values: const AudioProfileValues(eqGainsJson: '{bad json'),
      );
      final AudioProfileRow row =
          (await db.audioProfilesDao.forDevice('dev')).single;
      expect(AudioProfileCodec.fromRow(row).eqGains, isEmpty);
    });
  });

  group('AudioEngineController', () {
    test('applies the stored profile to the engine on init', () async {
      await db.audioProfilesDao.upsert(
        deviceKey: 'device-1',
        outputDeviceId: kDefaultOutputDeviceId,
        values: const AudioProfileValues(
          eqEnabled: true,
          eqGainsJson: '[6.0,0.0,0.0,0.0,-3.0]',
          bassBoost: 50,
          forceMono: true,
          replayGainMode: 'album',
        ),
      );
      final FakeCapableEngine engine = FakeCapableEngine();
      final FakeOutputDeviceTracker tracker =
          FakeOutputDeviceTracker(kDefaultOutputDeviceId);
      final AudioEngineController controller = AudioEngineController(
        db: db,
        deviceKeyFuture: Future<String>.value('device-1'),
        engineRef: () => engine,
        outputDeviceTracker: tracker,
      );
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.state.ready, isTrue);
      expect(controller.state.eqSupported, isTrue);
      expect(controller.state.effectsSupported, isTrue);
      expect(engine.eqEnabled, isTrue);
      expect(engine.gains, <double>[6, 0, 0, 0, -3]);
      expect(engine.appliedEffects?.bassBoost, 50);
      expect(engine.appliedEffects?.forceMono, isTrue);
      expect(
        controller.state.settings.replayGainMode,
        ReplayGainMode.album,
      );
    });

    test('mutations apply + persist into the profile table', () async {
      final FakeCapableEngine engine = FakeCapableEngine();
      final AudioEngineController controller = AudioEngineController(
        db: db,
        deviceKeyFuture: Future<String>.value('device-1'),
        engineRef: () => engine,
        outputDeviceTracker: FakeOutputDeviceTracker('default'),
      );
      addTearDown(controller.dispose);
      await controller.init();

      await controller.setBassBoost(70);
      await controller.setReplayGainPreamp(3);
      await controller.setCrossfadeSeconds(45); // clamps to 30
      await controller.setForceMono(true);

      expect(engine.appliedEffects?.bassBoost, 70);
      expect(engine.appliedEffects?.forceMono, isTrue);
      expect(controller.state.settings.crossfadeSeconds, 30);
      expect(controller.state.settings.replayGainPreampDb, 3);

      final AudioProfileRow stored = (await db.audioProfilesDao
              .forDevice('device-1'))
          .singleWhere((AudioProfileRow row) =>
              row.outputDeviceId == 'default');
      expect(stored.bassBoost, 70);
      expect(stored.crossfadeSeconds, 30);
      expect(stored.forceMono, isTrue);
    });

    test('switching output devices loads that device profile',
        () async {
      // Profile for the wired output only.
      await db.audioProfilesDao.upsert(
        deviceKey: 'device-1',
        outputDeviceId: 'wired-headphones',
        label: 'Wired',
        values: const AudioProfileValues(
          bassBoost: 100,
          eqGainsJson: '[12.0,0.0,0.0,0.0,0.0]',
        ),
      );
      final FakeCapableEngine engine = FakeCapableEngine();
      final FakeOutputDeviceTracker tracker =
          FakeOutputDeviceTracker('wired-headphones')
            ..labels['wired-headphones'] = 'Wired headphones';
      final AudioEngineController controller = AudioEngineController(
        db: db,
        deviceKeyFuture: Future<String>.value('device-1'),
        engineRef: () => engine,
        outputDeviceTracker: tracker,
      );
      addTearDown(controller.dispose);
      await controller.init();

      expect(controller.state.outputDeviceLabel, 'Wired headphones');
      expect(engine.appliedEffects?.bassBoost, 100);

      // Switch to an unknown device → defaults apply.
      tracker.switchTo('bt-car');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.outputDeviceId, 'bt-car');
      expect(controller.state.settings.bassBoostOf, 0);
      // Engine received the default (neutral) effects.
      expect(engine.appliedEffects?.bassBoost, 0);
    });
  });
}

extension on AudioSettingsState {
  /// Test-only alias to keep the assertion readable.
  int get bassBoostOf => effects.bassBoost;
}
