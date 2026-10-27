// authored, awaiting local run.
//
// Conditional-export smoke pair pivot (mirrors the pattern documented in
// `lib/playback/engines/engine_factory.dart`, whose doc comment points at
// this file for on-device engine testing).
//
// - On the VM / native arms this resolves to `engine_contract_smoke_arms.dart`
//   (dart:io present).
// - On web it resolves to `engine_contract_smoke_arms_web.dart`
//   (dart:js_interop present).
//
// Scope: real engines construct plugin objects (media_kit, just_audio,
// HTMLAudioElement), so these smoke tests stay MINIMAL — they assert the
// factory's exported symbols and the static type conformance of both
// platform engines against the abstract PlaybackEngine contract, and only
// attempt a guarded live construction (skipping with a documented reason
// when the native plugin libs are unavailable on the host flutter-tester).
// Full engine behaviour is on-device integration-test territory.
import 'engine_contract_smoke_arms.dart'
    if (dart.library.js_interop) 'engine_contract_smoke_arms_web.dart' as arms;

void main() => arms.runSmokeTests();
