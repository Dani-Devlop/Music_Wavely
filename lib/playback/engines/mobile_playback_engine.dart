import 'dart:async';

import 'package:audio_service/audio_service.dart' as asv;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

/// audio_service handler owned by [MobilePlaybackEngine] so the Android
/// notification / lock screen / iOS now-playing info reflect queue state.
///
/// Transport button presses are forwarded to the callbacks the engine wires
/// in its constructor. `AudioService.init` is NOT called by the composition
/// root: [MobilePlaybackEngine] initializes the service lazily and
/// idempotently on first playback (see `_ensureAudioService`).
class WavelyAudioHandler extends BaseAudioHandler {
  WavelyAudioHandler({
    void Function()? onPlay,
    void Function()? onPause,
    void Function(Duration position)? onSeek,
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onSeek = onSeek;

  final void Function()? _onPlay;
  final void Function()? _onPause;
  final void Function(Duration position)? _onSeek;

  @override
  Future<void> play() async => _onPlay?.call();

  @override
  Future<void> pause() async => _onPause?.call();

  @override
  Future<void> seek(Duration position) async => _onSeek?.call(position);
}

/// Mobile (Android / iOS) engine backed by just_audio, with the system
/// notification wired through [WavelyAudioHandler].
///
/// Queue semantics (Stage 1.1): engines are single-track loaders.
/// [setQueue] stores the list and loads `tracks[startIndex]`; advancing
/// within the queue is orchestrated by QueueManager which calls
/// [setQueue] again (or [skipTo] on the concrete class). The playback
/// contract therefore stays transport-agnostic.
class MobilePlaybackEngine implements PlaybackEngine {
  MobilePlaybackEngine({WavelyAudioHandler? notificationHandler})
      : _player = ja.AudioPlayer() {
    _handler = notificationHandler ??
        WavelyAudioHandler(onPlay: play, onPause: pause, onSeek: seek);
    _stateSub = _player.playerStateStream.listen(
      _onPlayerState,
      onError: (Object e, StackTrace st) => _emit(PlaybackState.error),
    );
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) => _emit(PlaybackState.error),
    );
    _positionSub = _player.positionStream.listen((p) {
      _position = p;
      if (!_positionController.isClosed) {
        _positionController.add(p);
      }
    });
  }

  static bool _audioSessionConfigured = false;

  /// One-time lazy `AudioService.init` future, shared per app run so the
  /// service is initialized exactly once even if several engine instances
  /// exist (only one does — this is belt and braces).
  static Future<void>? _audioServiceInitFuture;

  final ja.AudioPlayer _player;
  late final WavelyAudioHandler _handler;
  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<ja.PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _positionSub;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  List<Track> _queueTracks = const <Track>[];
  Track? _current;
  Duration _position = Duration.zero;
  PlaybackState _lastState = PlaybackState.stopped;
  bool _disposed = false;

  /// Configures the music audio-focus / interruption profile once per app
  /// run. Called lazily from [load]; may also be invoked from bootstrap.
  static Future<void> ensureAudioSession() async {
    if (_audioSessionConfigured) {
      return;
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioSessionConfigured = true;
  }

  /// Initializes audio_service lazily (idempotent per app run) so the media
  /// notification exists before the first playback starts. Failures are
  /// swallowed: playback must keep working without the notification (e.g.
  /// on platforms/tests without the audio_service channel).
  Future<void> _ensureAudioService() =>
      _audioServiceInitFuture ??= _initAudioService();

  Future<void> _initAudioService() async {
    try {
      await asv.AudioService.init(
        builder: () => _handler,
        config: const asv.AudioServiceConfig(
          androidNotificationChannelId: 'app.wavely.playback',
          androidNotificationChannelName: 'Wavely',
          androidNotificationOngoing: true,
        ),
      );
    } on Object catch (_) {
      // audio_service unavailable on this platform/run — continue without
      // the media notification.
    }
  }

  /// Handler instance to pass into `AudioService.init` (see class doc).
  WavelyAudioHandler get audioHandler => _handler;

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
    await ensureAudioSession();
    _current = t;
    _position = Duration.zero;
    _emit(PlaybackState.loading);
    try {
      await _player.setAudioSource(
        ja.AudioSource.uri(Uri.file(path)),
        initialPosition: startAt,
      );
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
    await _ensureAudioService();
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

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) {
      return;
    }
    await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());
  }

  /// Convenience for QueueManager-style callers that hold the concrete
  /// engine: loads [index] inside the queue stored by [setQueue].
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
    await _stateSub?.cancel();
    await _eventSub?.cancel();
    await _positionSub?.cancel();
    await _player.dispose();
    await _positionController.close();
    await _stateController.close();
  }

  void _onPlayerState(ja.PlayerState playerState) {
    final state = switch (playerState.processingState) {
      ja.ProcessingState.idle ||
      ja.ProcessingState.loading =>
        PlaybackState.loading,
      ja.ProcessingState.buffering => PlaybackState.buffering,
      ja.ProcessingState.ready => playerState.playing
          ? PlaybackState.playing
          : PlaybackState.paused,
      ja.ProcessingState.completed => PlaybackState.completed,
    };
    _emit(state);
  }

  void _emit(PlaybackState state) {
    if (_disposed || state == _lastState) {
      return;
    }
    _lastState = state;
    _stateController.add(state);
    _syncNotification(state);
  }

  /// Mirrors queue/playback state into the audio_service handler so the
  /// notification and lock screen always show the current track.
  void _syncNotification(PlaybackState state) {
    final track = _current;
    if (track == null) {
      return;
    }
    _handler.mediaItem.add(asv.MediaItem(
      id: '${track.id ?? track.sourceTrackId}',
      title: track.title,
      artist: track.artistOrUnknown,
      album: track.album,
      duration: Duration(milliseconds: track.durationMs),
      artUri: (track.coverPath != null && track.coverPath!.isNotEmpty)
          ? Uri.file(track.coverPath!)
          : null,
    ));
    final playing = state == PlaybackState.playing;
    final processing = switch (state) {
      PlaybackState.stopped => asv.AudioProcessingState.idle,
      PlaybackState.loading => asv.AudioProcessingState.loading,
      PlaybackState.buffering => asv.AudioProcessingState.buffering,
      PlaybackState.playing ||
      PlaybackState.paused =>
        asv.AudioProcessingState.ready,
      PlaybackState.completed => asv.AudioProcessingState.completed,
      PlaybackState.error => asv.AudioProcessingState.error,
    };
    _handler.playbackState.add(asv.PlaybackState(
      processingState: processing,
      playing: playing,
      controls: playing
          ? const <asv.MediaControl>[asv.MediaControl.pause]
          : const <asv.MediaControl>[asv.MediaControl.play],
      systemActions: const <asv.MediaAction>{asv.MediaAction.seek},
      updatePosition: _position,
    ));
  }
}
