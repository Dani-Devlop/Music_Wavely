import 'dart:async';
import 'dart:js_interop';

import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// Web engine implemented with a plain `HTMLAudioElement` through
/// `dart:js_interop` only (no package:web).
///
/// All DOM access goes through `JSObject.callMethod/getProperty/setProperty`
/// on `globalContext`; events use `addEventListener` with a converted Dart
/// tear-off (`.toJS`) — `allowInterop` is not needed with js_interop.
///
/// On web [Track.filePath] is interpreted as a playable URL (http(s), blob
/// or object URL), not a filesystem path.
class WebPlaybackEngine implements PlaybackEngine {
  WebPlaybackEngine() {
    final doc =
        globalContext.getProperty('document'.toJS) as JSObject;
    _audio = doc.callMethod('createElement'.toJS, 'audio'.toJS) as JSObject;
    _timeUpdateFn = _onTimeUpdate.toJS;
    _endedFn = _onEnded.toJS;
    _playingFn = _onPlaying.toJS;
    _pauseFn = _onPaused.toJS;
    _waitingFn = _onWaiting.toJS;
    _canPlayFn = _onCanPlay.toJS;
    _errorFn = _onError.toJS;
    _addEventListener('timeupdate', _timeUpdateFn);
    _addEventListener('ended', _endedFn);
    _addEventListener('playing', _playingFn);
    _addEventListener('pause', _pauseFn);
    _addEventListener('waiting', _waitingFn);
    _addEventListener('canplay', _canPlayFn);
    _addEventListener('error', _errorFn);
  }

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  late final JSObject _audio;
  late final JSFunction _timeUpdateFn;
  late final JSFunction _endedFn;
  late final JSFunction _playingFn;
  late final JSFunction _pauseFn;
  late final JSFunction _waitingFn;
  late final JSFunction _canPlayFn;
  late final JSFunction _errorFn;
  List<Track> _queueTracks = const <Track>[];
  PlaybackState _lastState = PlaybackState.stopped;
  bool _disposed = false;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    final src = t.filePath;
    if (src == null || src.isEmpty) {
      throw ArgumentError.value(t, 't', 'Track has no playable web src');
    }
    _emit(PlaybackState.loading);
    _audio.setProperty('src'.toJS, src.toJS);
    _audio.callMethod('load'.toJS);
    if (startAt != null) {
      // currentTime is writable before metadata loads in modern browsers;
      // applied once the element can play.
      _setCurrentTime(startAt);
    }
    _emit(PlaybackState.paused);
  }

  @override
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    // Returns a Promise; the result is intentionally ignored.
    _audio.callMethod('play'.toJS);
  }

  @override
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    _audio.callMethod('pause'.toJS);
  }

  @override
  Future<void> seek(Duration p) async {
    if (_disposed) {
      return;
    }
    _setCurrentTime(p);
    _positionController.add(p);
  }

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    _queueTracks = List<Track>.of(tracks);
    var index = startIndex;
    if (index < 0) {
      index = 0;
    }
    if (index >= _queueTracks.length) {
      index = _queueTracks.isEmpty ? 0 : _queueTracks.length - 1;
    }
    if (_queueTracks.isEmpty) {
      return;
    }
    await load(_queueTracks[index]);
  }

  /// Loads [index] inside the queue stored by [setQueue] (concrete-class
  /// convenience mirroring the other engines' skipTo).
  Future<bool> skipTo(int index) async {
    if (index < 0 || index >= _queueTracks.length) {
      return false;
    }
    await load(_queueTracks[index]);
    return true;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _removeEventListener('timeupdate', _timeUpdateFn);
    _removeEventListener('ended', _endedFn);
    _removeEventListener('playing', _playingFn);
    _removeEventListener('pause', _pauseFn);
    _removeEventListener('waiting', _waitingFn);
    _removeEventListener('canplay', _canPlayFn);
    _removeEventListener('error', _errorFn);
    _audio.callMethod('pause'.toJS);
    _audio.setProperty('src'.toJS, ''.toJS);
    await _positionController.close();
    await _stateController.close();
  }

  // -- JS plumbing ---------------------------------------------------------

  void _addEventListener(String type, JSFunction fn) {
    _audio.callMethod('addEventListener'.toJS, type.toJS, fn);
  }

  void _removeEventListener(String type, JSFunction fn) {
    _audio.callMethod('removeEventListener'.toJS, type.toJS, fn);
  }

  double _currentTime() =>
      (_audio.getProperty('currentTime'.toJS) as JSNumber).toDartDouble;

  void _setCurrentTime(Duration position) {
    _audio.setProperty(
      'currentTime'.toJS,
      (position.inMilliseconds / 1000).toJS,
    );
  }

  // -- DOM event handlers (converted via .toJS, JS-typed params only) ------

  void _onTimeUpdate(JSObject event) {
    if (_disposed) {
      return;
    }
    final seconds = _currentTime();
    _positionController
        .add(Duration(milliseconds: (seconds * 1000).round()));
  }

  void _onEnded(JSObject event) => _emit(PlaybackState.completed);

  void _onPlaying(JSObject event) => _emit(PlaybackState.playing);

  void _onPaused(JSObject event) {
    // `pause` also fires right before `ended`; never downgrade completed.
    if (_lastState == PlaybackState.completed) {
      return;
    }
    _emit(PlaybackState.paused);
  }

  void _onWaiting(JSObject event) => _emit(PlaybackState.buffering);

  void _onCanPlay(JSObject event) {
    if (_lastState == PlaybackState.completed ||
        _lastState == PlaybackState.playing) {
      return;
    }
    _emit(PlaybackState.paused);
  }

  void _onError(JSObject event) => _emit(PlaybackState.error);

  void _emit(PlaybackState state) {
    if (_disposed || state == _lastState) {
      return;
    }
    _lastState = state;
    _stateController.add(state);
  }
}
