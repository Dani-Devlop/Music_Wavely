/// Media Session API wiring for the web engine (Stage 2.2).
///
/// WEB-ONLY: imported exclusively from `playback_engine_web.dart` (the
/// conditional web arm of the engine factory), so `dart:js_interop` never
/// leaks onto io platforms.
///
/// Wires lock-screen / notification media controls (play, pause,
/// previoustrack, nexttrack) plus `MediaMetadata` (title, artist, album).
/// Every JS touchpoint is guarded — unsupported browsers degrade to a
/// no-op. The engine interaction is injected as callbacks so this class
/// stays independent of the concrete engine type.
library;

import 'dart:async';
import 'dart:js_interop';

/// Pure-Dart metadata payload builder (unit-testable without a browser).
Map<String, String> buildMediaMetadataPayload({
  required String title,
  required String artist,
  String album = '',
  String? artworkUrl,
}) =>
    <String, String>{
      'title': title,
      'artist': artist,
      'album': album,
      if (artworkUrl != null && artworkUrl.isNotEmpty) 'artwork': artworkUrl,
    };

/// Media Session host: registers action handlers and pushes metadata on
/// every playback-state change.
class PwaMediaSession {
  PwaMediaSession._({
    required Stream<Object?> stateStream,
    required Map<String, String> Function() metadata,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onPrevious,
    required Future<void> Function() onNext,
  })  : _metadata = metadata {
    _subscription = stateStream.listen((Object? _) => updateMetadata());
    _setHandler('play', onPlay);
    _setHandler('pause', onPause);
    _setHandler('previoustrack', onPrevious);
    _setHandler('nexttrack', onNext);
  }

  /// Attaches media-session wiring; returns the host (call [dispose] with
  /// the engine). Never throws — unsupported browsers get an inert host.
  static PwaMediaSession attach({
    required Stream<Object?> stateStream,
    required Map<String, String> Function() metadata,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onPrevious,
    required Future<void> Function() onNext,
  }) =>
      PwaMediaSession._(
        stateStream: stateStream,
        metadata: metadata,
        onPlay: onPlay,
        onPause: onPause,
        onPrevious: onPrevious,
        onNext: onNext,
      );

  StreamSubscription<Object?>? _subscription;
  final Map<String, String> Function() _metadata;

  /// Pushes fresh metadata into `navigator.mediaSession.metadata`.
  void updateMetadata() {
    try {
      final JSObject session = _mediaSession();
      final JSObject json = globalContext.getProperty('JSON'.toJS) as JSObject;
      final JSString payload =
          json.callMethod<JSString>('stringify'.toJS, _metadata().jsify());
      final JSObject ctor =
          globalContext.getProperty('MediaMetadata'.toJS) as JSObject;
      final JSObject metadataObject =
          ctor.callAsConstructor<JSObject>(payload);
      session.setProperty('metadata'.toJS, metadataObject);
    } on Object {
      // Unsupported browser → no-op.
    }
  }

  /// Cancels the state subscription (handlers stay; the browser GCs them
  /// with the page).
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _setHandler(String action, Future<void> Function() handler) {
    try {
      final JSObject session = _mediaSession();
      session.callMethod(
        'setActionHandler'.toJS,
        action.toJS,
        (() => handler()).toJS,
      );
    } on Object {
      // Unsupported action/browser → no-op.
    }
  }

  static JSObject _mediaSession() {
    final JSObject navigator =
        globalContext.getProperty('navigator'.toJS) as JSObject;
    return navigator.getProperty('mediaSession'.toJS) as JSObject;
  }
}
