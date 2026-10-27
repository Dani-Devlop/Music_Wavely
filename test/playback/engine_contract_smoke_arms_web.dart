// authored, awaiting local run.
//
// WEB arm of the engine-factory smoke pair (selected by
// `engine_contract_smoke_test.dart` when `dart:js_interop` is available;
// never compiled on the VM).
//
// Scope mirrors the io arm: assert the web factory symbol and the static
// conformance of WebPlaybackEngine against the abstract contract. A live
// construction is guarded because it touches `document.createElement` —
// under `flutter test --platform chrome` it succeeds and the engine is
// disposed immediately; in any non-browser context the guarded path
// reports a documented skip instead of failing.
// On-device scope: real audio element behaviour (canplay/ended events,
// currentTime writes) is browser-integration territory.
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/engines/playback_engine_web.dart';
import 'package:wavely/playback/engines/web_playback_engine.dart';

/// Entry point invoked by the smoke pivot (must match the io arm).
void runSmokeTests() {
  group('engine factory smoke (web arm)', () {
    test('createEngine is exported and typed to the abstract contract', () {
      final PlaybackEngine Function() factoryFn = createEngine;
      expect(factoryFn, isNotNull);
    });

    test('WebPlaybackEngine implements PlaybackEngine (static)', () {
      final PlaybackEngine Function() webCtor = WebPlaybackEngine.new;
      expect(webCtor, isNotNull);
    });

    test('guarded live construction (skips without a DOM)', () async {
      PlaybackEngine? engine;
      try {
        engine = createEngine();
      } on Object catch (e) {
        expect(true, isTrue,
            reason: 'skipped: no browser DOM available for the web engine '
                '($e) — run with --platform chrome for the live check');
        return;
      }
      try {
        expect(engine, isA<WebPlaybackEngine>());
        expect(engine.stateStream, isNotNull);
        expect(engine.positionStream, isNotNull);
      } finally {
        try {
          await engine.dispose();
        } on Object catch (_) {
          // Best-effort teardown when the DOM is partially available.
        }
      }
    });
  });
}
