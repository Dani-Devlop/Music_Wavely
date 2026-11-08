import 'dart:async';

import 'package:audio_service/audio_service.dart' as asv;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/headset_rules.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/equalizer/eq_presets.dart';
import 'package:wavely/playback/equalizer/equalizer_control.dart';

/// Media-session button offsets for the headset long-press FF/RW rule and
/// the lock-screen press-and-hold seek (Musicolet parity, Phase 9.4).
const Duration _seekStep = Duration(seconds: 10);

/// audio_service handler owned by [MobilePlaybackEngine] so the Android
/// notification / lock screen / iOS now-playing info reflect queue state.
///
/// Transport button presses are forwarded to the callbacks the engine wires
/// in its constructor; skip-to-next/previous and play/pause toggling come
/// from the queue layer via [MobilePlaybackEngine.setTransportCallbacks].
///
/// Phase 9.1 (lock screen): the handler publishes the full queue, album
/// art, a live seekbar (`systemActions: seek + seekForward/seekBackward`)
/// and optional lyrics (MediaItem extras) so lock screen / Android Auto
/// surfaces show the same state as the in-app player.
///
/// Phase 9.4 (headset): `onSeekForward`/`onSeekBackward` implement the
/// press-and-hold fast-forward/rewind rule (+/- 10s steps).
///
/// `AudioService.init` is NOT called by the composition root:
/// [MobilePlaybackEngine] initializes the service lazily and idempotently
/// on first playback (see `_ensureAudioService`).
class WavelyAudioHandler extends asv.BaseAudioHandler {
  WavelyAudioHandler({
    void Function()? onPlay,
    void Function()? onPause,
    Future<void> Function(Duration position)? onSeek,
    void Function()? onNext,
    void Function()? onPrevious,
    void Function()? onTogglePlayPause,
  })  : _onPlay = onPlay,
        _onPause = onPause,
        _onSeek = onSeek,
        _onNext = onNext,
        _onPrevious = onPrevious,
        _onTogglePlayPause = onTogglePlayPause;

  final void Function()? _onPlay;
  final void Function()? _onPause;
  final Future<void> Function(Duration position)? _onSeek;
  void Function()? _onNext;
  void Function()? _onPrevious;
  final void Function()? _onTogglePlayPause;

  /// Live position snapshot used by the relative-seek rules.
  Duration position = Duration.zero;

  /// Live duration snapshot used to clamp relative seeks.
  Duration duration = Duration.zero;

  /// True while the handler should advertise play (vs pause) as the
  /// primary button — mirrors the last synced playback state.
  bool playing = false;

  /// Registers the queue-layer transport callbacks (QueueManager).
  void setQueueCallbacks({
    void Function()? onNext,
    void Function()? onPrevious,
  }) {
    _onNext = onNext;
    _onPrevious = onPrevious;
  }

  @override
  Future<void> play() async => _onPlay?.call();

  @override
  Future<void> pause() async => _onPause?.call();

  @override
  Future<void> seek(Duration position) async => _onSeek?.call(position);

  @override
  Future<void> skipToNext() async => _onNext?.call();

  @override
  Future<void> skipToPrevious() async => _onPrevious?.call();

  /// Headset / lock-screen press-and-hold fast-forward (+10s).
  @override
  Future<void> seekForward(bool begin) async => seekBy(_seekStep);

  /// Headset / lock-screen press-and-hold rewind (-10s).
  @override
  Future<void> seekBackward(bool begin) async => seekBy(-_seekStep);

  /// Some platforms deliver the discrete fast-forward/rewind buttons
  /// instead of the press-and-hold events.
  @override
  Future<void> fastForward() async => seekBy(_seekStep);

  @override
  Future<void> rewind() async => seekBy(-_seekStep);

  /// Maps headset multi-click gestures: single click toggles play/pause,
  /// double click next, triple click previous (audio_service routes the
  /// counting on Android and delivers the resolved [asv.MediaButton]).
  @override
  Future<void> click([asv.MediaButton button = asv.MediaButton.media]) async {
    switch (button) {
      case asv.MediaButton.next:
        await skipToNext();
      case asv.MediaButton.previous:
        await skipToPrevious();
      case _:
        _onTogglePlayPause?.call();
    }
  }

  /// Applies a relative seek clamped to `[0, duration]` (FF/RW rule).
  Future<void> seekBy(Duration offset) async {
    final onSeek = _onSeek;
    if (onSeek == null) {
      return;
    }
    final target = position + offset;
    if (target < Duration.zero) {
      unawaited(onSeek(Duration.zero));
      return;
    }
    if (duration > Duration.zero && target > duration) {
      unawaited(onSeek(duration));
      return;
    }
    unawaited(onSeek(target));
  }

  /// Rebuilds the media item for the current track (lock screen art /
  /// seekbar / lyrics) and pushes the queue for lock screen / Android Auto
  /// browsing surfaces.
  void syncTrack(Track? track, {String? lyrics, List<Track>? queue}) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(_mediaItemFor(track, lyrics));
    if (queue != null && queue.isNotEmpty) {
      this.queue.add(
            queue.map(_mediaItemFor).toList(growable: false),
          );
    }
  }

  /// Publishes the playback state (controls, seekbar position, speed).
  void syncState(
    PlaybackState state, {
    required Duration position,
    required Duration duration,
  }) {
    this.position = position;
    this.duration = duration;
    playing = state == PlaybackState.playing;
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
    playbackState.add(asv.PlaybackState(
      processingState: processing,
      playing: playing,
      controls: _controls(state),
      systemActions: const <asv.MediaAction>{
        asv.MediaAction.seek,
        asv.MediaAction.seekForward,
        asv.MediaAction.seekBackward,
      },
      updatePosition: position,
      bufferedPosition: duration > position ? duration : position,
      speed: playing ? 1.0 : 0.0,
    ));
  }

  /// Full control strip: prev | play/pause | next (Musicolet parity).
  List<asv.MediaControl> _controls(PlaybackState state) {
    switch (state) {
      case PlaybackState.playing:
        return const <asv.MediaControl>[
          asv.MediaControl.skipToPrevious,
          asv.MediaControl.pause,
          asv.MediaControl.skipToNext,
        ];
      case PlaybackState.paused:
        return const <asv.MediaControl>[
          asv.MediaControl.skipToPrevious,
          asv.MediaControl.play,
          asv.MediaControl.skipToNext,
        ];
      case PlaybackState.loading:
      case PlaybackState.buffering:
        return const <asv.MediaControl>[];
      case PlaybackState.stopped:
      case PlaybackState.completed:
      case PlaybackState.error:
        return const <asv.MediaControl>[
          asv.MediaControl.play,
        ];
    }
  }

  asv.MediaItem _mediaItemFor(Track track, [String? lyrics]) => asv.MediaItem(
        id: '${track.id ?? track.sourceTrackId}',
        title: track.title,
        artist: track.artistOrUnknown,
        album: track.album,
        duration: Duration(milliseconds: track.durationMs),
        artUri: (track.coverPath != null && track.coverPath!.isNotEmpty)
            ? Uri.file(track.coverPath!)
            : null,
        // Lyrics ride the extras map: Android Auto / wear targets that
        // support it read them, everything else ignores the extra.
        extras: lyrics == null ? null : <String, dynamic>{'lyrics': lyrics},
      );
}

/// Mobile (Android / iOS) engine backed by just_audio, with the system
/// notification wired through [WavelyAudioHandler].
///
/// Queue semantics (Stage 1.1): engines are single-track loaders.
/// [setQueue] stores the list and loads `tracks[startIndex]`; advancing
/// within the queue is orchestrated by QueueManager which calls
/// [setQueue] again (or [skipTo] on the concrete class). The playback
/// contract therefore stays transport-agnostic.
class MobilePlaybackEngine implements PlaybackEngine, EqualizerControl {
  /// Creates the engine. On Android the just_audio player is constructed
  /// with an [ja.AudioPipeline] holding one [ja.AndroidEqualizer] (Stage 4
  /// DAP feature 2.2); every other platform keeps the previous no-pipeline
  /// construction so behaviour is byte-for-byte unchanged.
  MobilePlaybackEngine({WavelyAudioHandler? notificationHandler})
      : this._withEqualizer(
          notificationHandler: notificationHandler,
          equalizer: _AndroidEqualizerBundle.createForPlatform(),
        );

  MobilePlaybackEngine._withEqualizer({
    required WavelyAudioHandler? notificationHandler,
    required _AndroidEqualizerBundle? equalizer,
  })  : _eq = equalizer,
        _player = ja.AudioPlayer(
          audioPipeline: equalizer == null
              ? null
              : ja.AudioPipeline(
                  androidAudioEffects: <ja.AndroidAudioEffect>[
                    equalizer.effect,
                  ],
                ),
        ) {
    _handler = notificationHandler ??
        WavelyAudioHandler(
          onPlay: play,
          onPause: pause,
          onSeek: seek,
          onTogglePlayPause: () => _handlerProxyToggle?.call(),
        );
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
    // Phase 9.4: headset unplug / BT disconnect pause (becoming-noisy) is
    // bound together with the focus-interruption rules on first load — see
    // _bindSystemEventsOnce (the audio session instance must exist first).
  }

  static bool _audioSessionConfigured = false;

  /// One-time lazy `AudioService.init` future, shared per app run so the
  /// service is initialized exactly once even if several engine instances
  /// exist (only one does — this is belt and braces).
  static Future<void>? _audioServiceInitFuture;

  final ja.AudioPlayer _player;
  final _AndroidEqualizerBundle? _eq;
  late final HeadsetPlaybackRules _rules = HeadsetPlaybackRules(
    pause: pause,
    play: play,
    isPlaying: () => _lastState == PlaybackState.playing,
  );
  late final WavelyAudioHandler _handler;
  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<ja.PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  List<Track> _queueTracks = const <Track>[];
  Track? _current;
  Duration _position = Duration.zero;
  String? _lyrics;
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

  // --- Phase 9: transport callbacks / relative seek / lyrics ----------------

  @override
  void setTransportCallbacks({
    void Function()? onNext,
    void Function()? onPrevious,
    void Function()? onTogglePlayPause,
  }) {
    _handler.setQueueCallbacks(onNext: onNext, onPrevious: onPrevious);
    _handlerProxyToggle = onTogglePlayPause;
  }

  /// Toggle callback bridging the handler (assigned through
  /// [setTransportCallbacks]; the handler was constructed before the queue
  /// layer existed so the indirection goes through this mutable slot).
  void Function()? _handlerProxyToggle;

  /// Whether the system-event bindings (becoming-noisy + focus
  /// interruptions) are already attached — bound once, on first load.
  bool _systemEventsBound = false;

  /// Binds the headset/BT rules to the audio session's becoming-noisy and
  /// focus-interruption streams (Phase 9.4: unplug pause, BT/call rules,
  /// auto-resume). Called after [ensureAudioSession] — the session instance
  /// is only safe to touch once configured.
  Future<void> _bindSystemEventsOnce() async {
    if (_systemEventsBound) {
      return;
    }
    _systemEventsBound = true;
    try {
      final session = await AudioSession.instance;
      _rules.bindBecomingNoisy(session.becomingNoisyEventStream);
      _interruptionSub = session.interruptionEventStream.listen(
        _rules.handleInterruption,
        onError: (Object e, StackTrace st) {},
      );
    } on Object {
      // audio_session unavailable (tests / exotic platforms) — the rules
      // stay inert and playback keeps working.
      _systemEventsBound = false;
    }
  }

  @override
  Future<void> seekBy(Duration offset) async {
    if (_disposed) {
      return;
    }
    final target = _position + offset;
    if (target < Duration.zero) {
      await seek(Duration.zero);
      return;
    }
    final total = _current != null
        ? Duration(milliseconds: _current!.durationMs)
        : Duration.zero;
    if (total > Duration.zero && target > total) {
      await seek(total);
      return;
    }
    await seek(target);
  }

  @override
  Future<void> setLyrics(String? lyrics) async {
    _lyrics = lyrics;
    final track = _current;
    if (track != null) {
      _handler.syncTrack(track, lyrics: _lyrics, queue: _queueTracks);
    }
  }

  // --- Stage 4: equalizer capability (EqualizerControl) ---------------------

  /// Generous cap on the AndroidEqualizer handshake: on a platform where
  /// the pipeline was never activated the `parameters` future never
  /// completes, and a controller probing the engine must not hang forever.
  static const Duration _eqHandshakeTimeout = Duration(milliseconds: 1500);

  @override
  bool get equalizerAvailable => _eq != null;

  @override
  Future<EqualizerInfo?> queryEqualizer() async {
    final _AndroidEqualizerBundle? bundle = _eq;
    if (bundle == null) {
      return null;
    }
    try {
      final ja.AndroidEqualizerParameters params = await bundle.effect
          .parameters
          .timeout(
            _eqHandshakeTimeout,
            onTimeout: () => throw TimeoutException('equalizer handshake'),
          );
      return EqualizerInfo(
        bandCount: params.bands.length,
        bandFrequencies: params.bands
            .map((ja.AndroidEqualizerBand band) => band.centerFrequency)
            .toList(growable: false),
        minGainDb: params.minDecibels,
        maxGainDb: params.maxDecibels,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> setEqualizerEnabled({required bool enabled}) async {
    final _AndroidEqualizerBundle? bundle = _eq;
    if (bundle == null) {
      return false;
    }
    try {
      await bundle.effect.setEnabled(enabled);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> setEqualizerBandGain(int bandIndex, double gainDb) async {
    final _AndroidEqualizerBundle? bundle = _eq;
    if (bundle == null) {
      return false;
    }
    try {
      final ja.AndroidEqualizerParameters params = await bundle.effect
          .parameters
          .timeout(
            _eqHandshakeTimeout,
            onTimeout: () => throw TimeoutException('equalizer handshake'),
          );
      if (bandIndex < 0 || bandIndex >= params.bands.length) {
        return false;
      }
      await params.bands[bandIndex].setGain(EqualizerGains.clamp(gainDb));
      return true;
    } on Object {
      return false;
    }
  }

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
    await _bindSystemEventsOnce();
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
    await _rules.dispose();
    await _interruptionSub?.cancel();
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
    _handler.syncTrack(track, lyrics: _lyrics, queue: _queueTracks);
    _handler.syncState(
      state,
      position: _position,
      duration: Duration(milliseconds: track.durationMs),
    );
  }
}

/// Just_audio Android equalizer holder (Stage 4).
///
/// Exists so the redirecting constructor can build the player pipeline and
/// keep the [ja.AndroidEqualizer] reference in one value; `null` means "no
/// EQ on this platform" (desktop / iOS / tests).
class _AndroidEqualizerBundle {
  _AndroidEqualizerBundle(this.effect);

  /// The single equalizer effect owned by this engine instance.
  final ja.AndroidEqualizer effect;

  /// Creates the bundle only on native Android — the just_audio Android
  /// audio effects are no-ops everywhere else.
  static _AndroidEqualizerBundle? createForPlatform() {
    if (!PlatformUtils.isAndroid) {
      return null;
    }
    return _AndroidEqualizerBundle(ja.AndroidEqualizer());
  }
}
