import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/web/pwa_media_session.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/engines/web_playback_engine.dart';

/// Web engine factory (selected by the conditional import in
/// engine_factory.dart when `dart.library.js_interop` is available).
///
/// Stage 2.2: additionally wires the Media Session API (lock-screen
/// controls + metadata). The wiring is best-effort and fully guarded —
/// on unsupported browsers playback is untouched.
PlaybackEngine createEngine() {
  final WebPlaybackEngine engine = WebPlaybackEngine();
  _attachMediaSession(engine);
  return engine;
}

void _attachMediaSession(WebPlaybackEngine engine) {
  try {
    // The subscription lives for the page lifetime (the engine is a
    // process-wide singleton on web), so no explicit disposal is wired.
    PwaMediaSession.attach(
      stateStream: engine.stateStream,
      metadata: () {
        final Track? track = engine.currentTrack;
        if (track == null) {
          return const <String, String>{};
        }
        return buildMediaMetadataPayload(
          title: track.title,
          artist: track.artistOrUnknown,
        );
      },
      onPlay: () => engine.play(),
      onPause: () => engine.pause(),
      onPrevious: () async {
        final int target = engine.currentIndex - 1;
        if (target >= 0) {
          await engine.skipTo(target);
        }
      },
      onNext: () async {
        final int target = engine.currentIndex + 1;
        if (target < 0) {
          return;
        }
        await engine.skipTo(target);
      },
    );
  } on Object {
    // Media Session unsupported → plain playback, unchanged behaviour.
  }
}
