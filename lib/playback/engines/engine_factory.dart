import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/engines/playback_engine_stub.dart'
    if (dart.library.js_interop) 'package:wavely/playback/engines/playback_engine_web.dart'
    if (dart.library.io) 'package:wavely/playback/engines/playback_engine_io.dart';

/// Provides the platform playback engine (media_kit on desktop, just_audio
/// on mobile, HTMLAudioElement on web).
///
/// Widget tests override this with a fake engine; the real engines can only
/// be exercised on-device via integration_test (see
/// test/playback/engine_contract_smoke_test.dart).
final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = createEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
