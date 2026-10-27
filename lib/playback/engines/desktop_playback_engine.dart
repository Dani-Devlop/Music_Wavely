import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// Desktop (Windows / macOS / Linux) engine backed by media_kit.
///
/// Queue semantics (Stage 1.1): engines are single-track loaders —
/// [setQueue] stores the list and loads `tracks[startIndex]`; queue
/// advancement lives in QueueManager (see MobilePlaybackEngine doc).
///
/// media_kit 1.2.x API notes (verified against pub.dev docs):
/// - `MediaKit.ensureInitialized()` for native libs.
/// - `Player.open(Playlist, {bool play})` — a single [Media] is opened via
///   `open(Playlist([Media(path)]))`; here we pass play:false and let the
///   caller drive play/pause.
/// - Events via `player.stream` (singular; `streams` is deprecated):
///   `.position/.duration/.playing/.completed/.buffering/.error/.rate`.
class DesktopPlaybackEngine implements PlaybackEngine {
  DesktopPlaybackEngine() {
    if (!_nativeInitialized) {
      MediaKit.ensureInitialized();
      _nativeInitialized = true;
    }
    _player = Player();
    _positionSub =
        _player.stream.position.listen((p) => _positionController.add(p));
    _playingSub = _player.stream.playing.listen(_onPlaying);
    _completedSub = _player.stream.completed.listen(_onCompleted);
    _errorSub = _player.stream.error.listen((_) => _emit(PlaybackState.error));
  }

  static bool _nativeInitialized = false;

  late final Player _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<String>? _errorSub;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  List<Track> _queueTracks = const <Track>[];
  PlaybackState _lastState = PlaybackState.stopped;
  bool _disposed = false;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<PlaybackState> get stateStream => _stateController.stream;

  @override
  Future<void> load(Track t, {Duration? startAt}) async {
    final path = t.filePath;
    if (path == null || path.isEmpty) {
      // QueueManager guards this; throwing keeps the contract explicit.
      throw ArgumentError.value(t, 't', 'Track has no local filePath');
    }
    _emit(PlaybackState.loading);
    try {
      // `play: false` — QueueManager decides when to start playback.
      await _player.open(Playlist(<Media>[Media(path)]), play: false);
      if (startAt != null) {
        await _player.seek(startAt);
      }
    } on Object {
      _emit(PlaybackState.error);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) {
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    await _player.pause();
  }

  @override
  Future<void> seek(Duration p) async {
    if (_disposed) {
      return;
    }
    await _player.seek(p);
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
  /// convenience mirroring MobilePlaybackEngine.skipTo).
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
    await _positionSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    await _player.dispose();
    await _positionController.close();
    await _stateController.close();
  }

  void _onPlaying(bool playing) {
    // `completed` fires together with playing=false; never downgrade an
    // already reported completed state back to paused.
    if (!playing && _lastState == PlaybackState.completed) {
      return;
    }
    _emit(playing ? PlaybackState.playing : PlaybackState.paused);
  }

  void _onCompleted(bool completed) {
    if (completed) {
      _emit(PlaybackState.completed);
    }
  }

  void _emit(PlaybackState state) {
    if (_disposed || state == _lastState) {
      return;
    }
    _lastState = state;
    _stateController.add(state);
  }
}
