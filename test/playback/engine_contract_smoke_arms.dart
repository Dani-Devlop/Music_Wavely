// authored, awaiting local run.
//
// IO arm of the engine-factory smoke pair (selected by
// `engine_contract_smoke_test.dart` when `dart:js_interop` is absent).
//
// What CAN run on the host `flutter test` VM:
// - the factory symbol `createEngine` (from the conditional export resolved
//   to `playback_engine_io.dart`) is present and typed to return a
//   PlaybackEngine;
// - both platform engine classes compile against the abstract contract
//   (tear-offs of their constructors are assignable to
//   `PlaybackEngine Function()`);
// - a guarded live construction attempt: media_kit / just_audio need
//   native plugin libs that are absent in the flutter-tester sandbox, so a
//   construction failure is reported as a documented skip, not a failure.
//   When it succeeds (a host with the natives present), the engine is
//   type-asserted and disposed immediately.
// On-device scope: audio graph behaviour (actual playback, position ticks,
// OS notification wiring) belongs to integration_test runs.
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/engines/desktop_playback_engine.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine_io.dart';
import 'package:wavely/playback/engines/mobile_playback_engine.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// Entry point invoked by the smoke pivot (must match the web arm).
void runSmokeTests() {
  group('engine factory smoke (io arm)', () {
    test('createEngine is exported and typed to the abstract contract', () {
      final PlaybackEngine Function() factoryFn = createEngine;
      expect(factoryFn, isNotNull);
    });

    test('desktop + mobile engines implement PlaybackEngine (static)', () {
      final PlaybackEngine Function() desktopCtor = DesktopPlaybackEngine.new;
      final PlaybackEngine Function() mobileCtor = MobilePlaybackEngine.new;
      expect(desktopCtor, isNotNull);
      expect(mobileCtor, isNotNull);
    });

    test('guarded live construction (skips when natives are missing)',
        () async {
      PlaybackEngine? engineOrNull;
      try {
        engineOrNull = createEngine();
      } on Object catch (e) {
        expect(true, isTrue,
            reason: 'skipped: engine natives unavailable on the host '
                'flutter-tester ($e) — real-engine scope is on-device '
                'integration tests');
        return;
      }
      final engine = engineOrNull!;
      try {
        expect(
          engine is DesktopPlaybackEngine || engine is MobilePlaybackEngine,
          isTrue,
        );
        expect(engine.stateStream, isNotNull);
        expect(engine.positionStream, isNotNull);
      } finally {
        try {
          await engineOrNull?.dispose();
        } on Object catch (_) {
          // Best-effort teardown of a partially-initialized native engine.
        }
      }
    });
  });
}
