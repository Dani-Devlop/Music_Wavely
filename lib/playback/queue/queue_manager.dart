import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';
import 'package:wavely/playback/shuffle/basic_shuffle.dart';

part 'queue_manager.freezed.dart';

/// Immutable snapshot of the whole playback queue owned by [QueueManager].
@freezed
abstract class QueueState with _$QueueState {
  const factory QueueState({
    @Default(<Track>[]) List<Track> tracks,
    @Default(0) int currentIndex,
    @Default(RepeatMode.off) RepeatMode repeatMode,
    @Default(false) bool shuffleEnabled,
    @Default(PlaybackState.stopped) PlaybackState playbackState,
    required Duration position,
    required Duration duration,
    @Default(1.0) double speed,
    DateTime? sleepTimerEndsAt,
  }) = _QueueState;

  const QueueState._();

  bool get hasCurrent => tracks.isNotEmpty && currentIndex < tracks.length;

  Track? get currentTrack => hasCurrent ? tracks[currentIndex] : null;
}

/// Resolves persisted queue ids back to [Track]s on [QueueManager.restore].
///
/// The composition root (Task 4) overrides [queueTrackSourceProvider] with a
/// Drift-backed implementation honoring the requested id order; the default
/// resolves to nothing so `restore()` is a no-op until wiring exists.
abstract interface class QueueTrackSource {
  Future<List<Track>> byIds(List<int> ids);
}

/// Parental-control preload decision for one track (Stage 1.2, B8).
///
/// Returned by [QueueManager.trackPreloadHook]; the manager never imports
/// the parental feature — the composition root adapts the verdict.
class TrackLoadDecision {
  const TrackLoadDecision._(this.replacementPath, this.skip,
      [this.muted = false]);

  /// Play the original file.
  const TrackLoadDecision.allow() : this._(null, false);

  /// Play [replacementPath] instead (e.g. a censored render).
  const TrackLoadDecision.replace(String path) : this._(path, false);

  /// Skip the track entirely (blocked by parental rules).
  const TrackLoadDecision.skip() : this._(null, true);

  /// Stage 3 final polish (BUG-9): play the original with the engine output
  /// muted — used by the censor-fallback policy when an explicit track
  /// cannot be censored and the parent chose "mute".
  const TrackLoadDecision.muted() : this._(null, false, true);

  final String? replacementPath;
  final bool skip;

  /// BUG-9: when true the track loads at engine volume 0 (silenced).
  final bool muted;
}

class _NullQueueTrackSource implements QueueTrackSource {
  const _NullQueueTrackSource();

  @override
  Future<List<Track>> byIds(List<int> ids) async => const <Track>[];
}

/// Default binding — overridden in the composition root (Task 4).
final queueTrackSourceProvider = Provider<QueueTrackSource>(
  (ref) => const _NullQueueTrackSource(),
);

/// Single source of truth for queue + playback UI state.
///
/// - Owns repeat/shuffle/queue mutations and persistence (three
///   [AppConstants] keys: queue ids CSV, index, position).
/// - Mirrors engine state/position streams into [QueueState].
/// - Engine semantics (Stage 1.1): engines are single-track loaders, so
///   advancing/reordering loads `tracks[currentIndex]` through
///   `engine.setQueue(tracks, startIndex: currentIndex)`.
class QueueManager extends StateNotifier<QueueState> {
  QueueManager({
    required PlaybackEngine engine,
    required SettingsStore store,
    QueueTrackSource? trackSource,
    this.onTrackStarted,
    this.advancedShuffleConfig,
    this.trackPreloadHook,
  })  : _engine = engine,
        _store = store,
        _trackSource = trackSource,
        super(
          const QueueState(position: Duration.zero, duration: Duration.zero),
        ) {
    _stateSub = engine.stateStream.listen(_onEngineState);
    _positionSub = engine.positionStream.listen((p) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(position: p);
    });
  }

  /// Positions beyond this point restart the track instead of skipping back.
  static const Duration _restartThreshold = Duration(seconds: 3);

  /// Called when a track actually begins playing within the current queue.
  /// Task 4 wires this to the play history recorder; wrapped in try/catch so
  /// recording can never break playback (see [_notifyTrackStarted]).
  final void Function(Track track)? onTrackStarted;

  /// Stage 1.2 (B7): when non-null, `toggleShuffle` runs the advanced
  /// pipeline with this configuration instead of [BasicShuffle]. Injected by
  /// the composition root from the persisted [ShuffleConfig].
  final ShuffleConfig? advancedShuffleConfig;

  /// Stage 1.2 (B8): parental preload hook. May return null (no parental
  /// policy → behave as allow). Blocking decisions make the manager skip to
  /// the next track; replacements swap the loaded file path. The hook is
  /// awaited OUTSIDE state mutations and its failures degrade to allow.
  final Future<TrackLoadDecision?> Function(Track track)? trackPreloadHook;

  final PlaybackEngine _engine;
  final SettingsStore _store;
  final QueueTrackSource? _trackSource;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _sleepTimer;
  List<Track>? _unshuffledTracks;
  int? _unshuffledIndex;

  /// Last track reported through [onTrackStarted] for the CURRENT queue
  /// (reset by [setQueue]); pause/resume and shuffle/reorder reloads of the
  /// same track must not record a second play.
  Track? _playedTrack;

  /// Replaces the whole queue and loads `tracks[startIndex]` (paused).
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    final list = List<Track>.of(tracks);
    var index = startIndex;
    if (list.isEmpty) {
      index = 0;
    } else {
      if (index < 0) {
        index = 0;
      }
      if (index >= list.length) {
        index = list.length - 1;
      }
    }
    _unshuffledTracks = List<Track>.of(list);
    _unshuffledIndex = index;
    // A new queue starts a fresh play-recording session; the hook itself
    // fires from [play] so a paused load (e.g. restore()) records nothing.
    _playedTrack = null;
    final track = list.isEmpty ? null : list[index];
    state = QueueState(
      tracks: list,
      currentIndex: index,
      repeatMode: state.repeatMode,
      shuffleEnabled: state.shuffleEnabled,
      playbackState:
          track == null ? PlaybackState.stopped : PlaybackState.loading,
      position: Duration.zero,
      duration: Duration(milliseconds: track?.durationMs ?? 0),
      speed: state.speed,
      sleepTimerEndsAt: state.sleepTimerEndsAt,
    );
    if (track != null) {
      await _loadCurrent();
    }
    _persist();
  }

  /// Optimistic play — the engine state stream reconciles afterwards.
  /// Fires [onTrackStarted] when playback transitions into `playing` for a
  /// track not yet recorded in this queue (setQueue-launched tracks, manual
  /// play, auto-advance via [next]/[previous], post-shuffle resume). A plain
  /// paused load records nothing — "track started" means sound was asked
  /// for, which keeps semantics unambiguous.
  Future<void> play() async {
    if (!state.hasCurrent) {
      return;
    }
    final wasAlreadyPlaying = state.playbackState == PlaybackState.playing;
    state = state.copyWith(playbackState: PlaybackState.playing);
    if (!wasAlreadyPlaying) {
      _notifyTrackStarted();
    }
    try {
      await _engine.play();
    } on Object catch (_) {
      state = state.copyWith(playbackState: PlaybackState.error);
    }
  }

  /// Optimistic pause — the engine state stream reconciles afterwards.
  Future<void> pause() async {
    if (!state.hasCurrent) {
      return;
    }
    state = state.copyWith(playbackState: PlaybackState.paused);
    try {
      await _engine.pause();
    } on Object catch (_) {
      state = state.copyWith(playbackState: PlaybackState.error);
    }
  }

  /// Toggles between [play] and [pause] based on the current state.
  Future<void> togglePlayPause() async =>
      state.playbackState == PlaybackState.playing ? pause() : play();

  /// Advances one track honouring repeat modes:
  /// - `one`: replay current track from zero.
  /// - `all`: wrap to index 0 at the end.
  /// - `off`: stop at the end ([PlaybackState.completed]).
  Future<void> next() async {
    final tracks = state.tracks;
    if (tracks.isEmpty) {
      return;
    }
    final repeat = state.repeatMode;
    if (repeat == RepeatMode.one) {
      state = state.copyWith(position: Duration.zero);
      await _guarded(() async {
        await _engine.seek(Duration.zero);
        await _engine.play();
      });
      return;
    }
    if (state.currentIndex >= tracks.length - 1) {
      if (repeat == RepeatMode.all) {
        await _goTo(0);
        return;
      }
      state = state.copyWith(
        playbackState: PlaybackState.completed,
        position: state.duration,
      );
      return;
    }
    await _goTo(state.currentIndex + 1);
  }

  /// Steps back one track; a mid-track position (> [_restartThreshold])
  /// restarts the current track instead.
  Future<void> previous() async {
    if (state.tracks.isEmpty) {
      return;
    }
    if (state.position > _restartThreshold) {
      await seek(Duration.zero);
      return;
    }
    final repeat = state.repeatMode;
    if (repeat == RepeatMode.all && state.currentIndex == 0) {
      await _goTo(state.tracks.length - 1);
      return;
    }
    if (state.currentIndex > 0) {
      await _goTo(state.currentIndex - 1);
      return;
    }
    await seek(Duration.zero);
  }

  /// Enables shuffle: keeps the original order/index and reorders — via
  /// [BasicShuffle] by default, or the advanced pipeline (B7) when an
  /// [advancedShuffleConfig] is wired. Disabling restores the original order
  /// at the original track position.
  Future<void> toggleShuffle() async {
    if (state.tracks.isEmpty) {
      return;
    }
    final wasPlaying = state.playbackState == PlaybackState.playing;
    if (!state.shuffleEnabled) {
      final recentIds = state.tracks
          .take(state.currentIndex)
          .map((t) => t.id)
          .whereType<int>()
          .toList();
      final window = recentIds.length > AppConstants.shuffleNoRepeatWindow
          ? recentIds.sublist(
              recentIds.length - AppConstants.shuffleNoRepeatWindow,
            )
          : recentIds;
      _unshuffledTracks ??= List<Track>.of(state.tracks);
      _unshuffledIndex ??= state.currentIndex;
      final config = advancedShuffleConfig;
      final shuffled = config == null
          ? const BasicShuffle().shuffle(
              state.tracks,
              currentIndex: state.currentIndex,
              seed: DateTime.now().millisecond,
              recentlyPlayedIds: window,
            )
          : const AdvancedShuffle().shuffle(
              state.tracks,
              currentIndex: state.currentIndex,
              config: config,
              recentlyPlayedIds: window,
            );
      state = state.copyWith(
        tracks: shuffled,
        currentIndex: 0,
        shuffleEnabled: true,
        position: Duration.zero,
        duration: Duration(milliseconds: shuffled.first.durationMs),
      );
      await _loadCurrent();
      if (wasPlaying) {
        unawaited(play());
      }
      _persist();
      return;
    }
    final original = _unshuffledTracks;
    final originalIndex = _unshuffledIndex;
    _unshuffledTracks = null;
    _unshuffledIndex = null;
    if (original == null || original.isEmpty) {
      state = state.copyWith(shuffleEnabled: false);
      return;
    }
    var index = originalIndex ?? 0;
    if (index >= original.length) {
      index = original.length - 1;
    }
    state = state.copyWith(
      tracks: original,
      currentIndex: index,
      shuffleEnabled: false,
      position: Duration.zero,
      duration: Duration(milliseconds: original[index].durationMs),
    );
    await _loadCurrent();
    if (wasPlaying) {
      unawaited(play());
    }
    _persist();
  }

  void setRepeatMode(RepeatMode mode) {
    state = state.copyWith(repeatMode: mode);
  }

  /// Stage 1.1 limitation: the [PlaybackEngine] contract has no rate API, so
  /// speed is tracked in state only (UI reflects the selection). It becomes
  /// effective once engines gain a rate method — no contract change happens
  /// here (the contract file is owned by the Task 2 stage).
  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }

  /// Seeks the engine and mirrors the position into state.
  Future<void> seek(Duration p) async {
    state = state.copyWith(position: p);
    try {
      await _engine.seek(p);
    } on Object catch (_) {
      state = state.copyWith(playbackState: PlaybackState.error);
    }
  }

  /// Moves a row for the queue sheet. Skips the engine reload when the
  /// current track is untouched so playback never restarts.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final tracks = List<Track>.of(state.tracks);
    if (oldIndex < 0 || oldIndex >= tracks.length) {
      return;
    }
    var target = newIndex;
    if (oldIndex < target) {
      target -= 1;
    }
    if (target < 0 || target >= tracks.length || target == oldIndex) {
      return;
    }
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(target, moved);
    var current = state.currentIndex;
    if (oldIndex == current) {
      current = target;
    } else if (oldIndex < current && target >= current) {
      current -= 1;
    } else if (oldIndex > current && target <= current) {
      current += 1;
    }
    final currentBefore = state.currentTrack;
    state = state.copyWith(tracks: tracks, currentIndex: current);
    final currentAfter = state.currentTrack;
    if (!identical(currentBefore, currentAfter) &&
        currentBefore != currentAfter) {
      await _loadCurrent();
    }
    _persist();
  }

  /// Removes a row. Removing the current track advances to the track that
  /// slides into its place (or stops when the queue empties); removing any
  /// other row never touches the engine.
  Future<void> removeFromQueue(int index) async {
    final tracks = List<Track>.of(state.tracks);
    if (index < 0 || index >= tracks.length) {
      return;
    }
    if (index != state.currentIndex) {
      tracks.removeAt(index);
      var current = state.currentIndex;
      if (index < current) {
        current -= 1;
      }
      state = state.copyWith(tracks: tracks, currentIndex: current);
      _persist();
      return;
    }
    final wasPlaying = state.playbackState == PlaybackState.playing;
    tracks.removeAt(index);
    if (tracks.isEmpty) {
      await _guarded(_engine.pause);
      state = QueueState(
        tracks: const <Track>[],
        repeatMode: state.repeatMode,
        shuffleEnabled: state.shuffleEnabled,
        playbackState: PlaybackState.stopped,
        position: Duration.zero,
        duration: Duration.zero,
        speed: state.speed,
      );
      _persist();
      return;
    }
    var newIndex = index;
    if (newIndex >= tracks.length) {
      newIndex = tracks.length - 1;
    }
    state = state.copyWith(
      tracks: tracks,
      currentIndex: newIndex,
      playbackState:
          wasPlaying ? PlaybackState.loading : PlaybackState.paused,
      position: Duration.zero,
      duration: Duration(milliseconds: tracks[newIndex].durationMs),
    );
    await _loadCurrent();
    if (wasPlaying) {
      unawaited(play());
    }
    _persist();
  }

  /// Pauses playback once [duration] elapses. Accepts any Duration so tests
  /// can use millisecond timers (presets come in minutes from the UI).
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, _onSleepTimerElapsed);
    state = state.copyWith(
      sleepTimerEndsAt: DateTime.now().add(duration),
    );
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(sleepTimerEndsAt: null);
  }

  /// Rebuilds the queue from persisted ids (CSV) + index + position.
  ///
  /// Never auto-plays: the engine only loads the persisted track, paused.
  /// Skips gracefully when no [QueueTrackSource] is wired or ids cannot be
  /// resolved.
  Future<void> restore() async {
    final source = _trackSource;
    if (source == null) {
      return;
    }
    final idsRaw =
        await _store.read<String>(AppConstants.queuePersistKey);
    if (idsRaw == null || idsRaw.isEmpty) {
      return;
    }
    final ids = idsRaw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    if (ids.isEmpty) {
      return;
    }
    List<Track> tracks;
    try {
      tracks = await source.byIds(ids);
    } on Object catch (_) {
      return;
    }
    if (tracks.isEmpty) {
      return;
    }
    final indexRaw =
        await _store.read<int>(AppConstants.queueIndexPersistKey);
    final positionMs = await _store.read<int>(
          AppConstants.queuePositionPersistKey,
        ) ??
        0;
    var index = indexRaw ?? 0;
    if (index < 0) {
      index = 0;
    }
    if (index >= tracks.length) {
      index = tracks.length - 1;
    }
    // Stage 3 audit (BUG-11): shuffle/repeat modes and the pre-shuffle order
    // are persisted; previously the shuffled order was silently adopted as
    // the "original" after a restart, losing the true album order.
    final shuffleRaw =
        await _store.read<int>(AppConstants.queueShufflePersistKey) ?? 0;
    final repeatRaw =
        await _store.read<int>(AppConstants.queueRepeatPersistKey) ?? 0;
    final originalIdsRaw =
        await _store.read<String>(AppConstants.queueOriginalPersistKey);
    var repeatIndex = repeatRaw;
    if (repeatIndex < 0) {
      repeatIndex = 0;
    }
    if (repeatIndex >= RepeatMode.values.length) {
      repeatIndex = RepeatMode.values.length - 1;
    }
    var unshuffled = List<Track>.of(tracks);
    var unshuffledIndex = index;
    if (shuffleRaw == 1 && originalIdsRaw != null && originalIdsRaw.isNotEmpty) {
      final wanted = originalIdsRaw
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();
      if (wanted.isNotEmpty) {
        final byId = <int, Track>{
          for (final t in tracks)
            if (t.id != null) t.id!: t,
        };
        final ordered = <Track>[
          for (final id in wanted)
            if (byId.containsKey(id)) byId[id]!,
        ];
        final orderedIds = ordered.map((t) => t.id).toSet();
        final missing =
            tracks.where((t) => !orderedIds.contains(t.id)).toList();
        unshuffled = [...ordered, ...missing];
        final currentId = tracks[index].id;
        final pos = unshuffled.indexWhere((t) => t.id == currentId);
        unshuffledIndex = pos >= 0 ? pos : index;
      }
    }
    state = state.copyWith(
      tracks: tracks,
      currentIndex: index,
      position: Duration(milliseconds: positionMs),
      duration: Duration(milliseconds: tracks[index].durationMs),
      playbackState: PlaybackState.stopped,
      shuffleEnabled: shuffleRaw == 1,
      repeatMode: RepeatMode.values[repeatIndex],
    );
    _unshuffledTracks = unshuffled;
    _unshuffledIndex = unshuffledIndex;
    await _loadCurrent();
    // Stage 3 audit (BUG-10): the persisted position was displayed but the
    // engine always restarted at 0:00. Seek to the persisted offset after
    // the initial load so resume actually resumes.
    if (positionMs > 0 && state.playbackState != PlaybackState.error) {
      try {
        await _engine.seek(Duration(milliseconds: positionMs));
      } on Object catch (_) {
        // A failed resume-seek must not break queue restore.
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_positionSub?.cancel());
    _sleepTimer?.cancel();
    _sleepTimer = null;
    super.dispose();
  }

  // -- internals -----------------------------------------------------------

  /// Invokes [onTrackStarted] at most once per track within the current
  /// queue; recording errors are swallowed so playback is never affected.
  void _notifyTrackStarted() {
    final callback = onTrackStarted;
    final track = state.currentTrack;
    if (callback == null || track == null) {
      return;
    }
    if (track == _playedTrack) {
      return;
    }
    _playedTrack = track;
    try {
      callback(track);
    } on Object catch (_) {
      // Recording a play must never break playback.
    }
  }

  /// (Re)loads the current track on the engine, guarding load failures
  /// (e.g. tracks without a local file) into an error playback state.
  ///
  /// Stage 1.2 (B8): when [trackPreloadHook] is wired, every candidate track
  /// passes through it first — `skip` advances to the next track (cyclic
  /// scan, bounded by one full pass so an all-blocked queue rests in
  /// `completed`), `replace` swaps the loaded file path, and hook failures
  /// degrade to allow (playback must never be bricked by the filter).
  Future<void> _loadCurrent({int skippedCount = 0}) async {
    var track = state.currentTrack;
    if (track == null) {
      return;
    }
    final hook = trackPreloadHook;
    // Stage 3 audit (BUG-2): `decision` was previously declared inside the
    // `if (hook != null)` block but read after it — a compile error. Hoisted.
    TrackLoadDecision? decision;
    if (hook != null) {
      try {
        decision = await hook(track);
      } on Object catch (_) {
        decision = null; // degrade to allow
      }
      if (!mounted) {
        return;
      }
      if (decision?.skip ?? false) {
        if (skippedCount >= state.tracks.length) {
          state = state.copyWith(
            playbackState: PlaybackState.completed,
            position: state.duration,
          );
          return;
        }
        final nextIndex = (state.currentIndex + 1) % state.tracks.length;
        state = state.copyWith(
          currentIndex: nextIndex,
          position: Duration.zero,
        );
        return _loadCurrent(skippedCount: skippedCount + 1);
      }
      final replacement = decision?.replacementPath;
      if (replacement != null) {
        track = track.copyWith(filePath: replacement);
      }
    }
    try {
      if (decision?.replacementPath != null) {
        await _engine.load(track);
      } else {
        await _engine.setQueue(state.tracks, startIndex: state.currentIndex);
      }
      // Stage 3 final polish (BUG-9): volume state is re-asserted after
      // every load — a `muted` decision plays silently, everything else
      // restores full volume (engines may keep volume across sources).
      await _engine.setVolume((decision?.muted ?? false) ? 0.0 : 1.0);
    } on Object catch (_) {
      state = state.copyWith(playbackState: PlaybackState.error);
    }
  }

  Future<void> _goTo(int index) async {
    final tracks = state.tracks;
    if (index < 0 || index >= tracks.length) {
      return;
    }
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: Duration(milliseconds: tracks[index].durationMs),
      playbackState: PlaybackState.loading,
    );
    await _loadCurrent();
    unawaited(play());
    _persist();
  }

  void _onEngineState(PlaybackState engineState) {
    // Engine events for an empty queue are meaningless (e.g. a trailing
    // paused emission after the queue was cleared) — keep the last
    // manager-authored state instead.
    if (!mounted || !state.hasCurrent) {
      return;
    }
    if (engineState != PlaybackState.completed) {
      state = state.copyWith(playbackState: engineState);
      return;
    }
    final repeat = state.repeatMode;
    if (repeat == RepeatMode.one) {
      state = state.copyWith(
        position: Duration.zero,
        playbackState: PlaybackState.playing,
      );
      unawaited(
        _guarded(() async {
          await _engine.seek(Duration.zero);
          await _engine.play();
        }),
      );
      return;
    }
    if (state.currentIndex + 1 < state.tracks.length) {
      unawaited(next());
      return;
    }
    // End of queue with repeat off: rest in completed.
    state = state.copyWith(
      playbackState: PlaybackState.completed,
      position: state.duration,
    );
  }

  void _onSleepTimerElapsed() {
    _sleepTimer = null;
    state = state.copyWith(
      sleepTimerEndsAt: null,
      playbackState: PlaybackState.paused,
    );
    unawaited(_guarded(_engine.pause));
  }

  /// Runs an engine call, turning failures into an error playback state
  /// (e.g. tracks without a local file).
  Future<void> _guarded(Future<void> Function() op) async {
    try {
      await op();
    } on Object catch (_) {
      state = state.copyWith(playbackState: PlaybackState.error);
    }
  }

  void _persist() {
    final ids = state.tracks
        .map((t) => t.id)
        .whereType<int>()
        .join(',');
    unawaited(_store.write(AppConstants.queuePersistKey, ids));
    unawaited(_store.write(AppConstants.queueIndexPersistKey, state.currentIndex));
    unawaited(
      _store.write(
        AppConstants.queuePositionPersistKey,
        state.position.inMilliseconds,
      ),
    );
    // Stage 3 audit (BUG-11): persist shuffle/repeat so they survive restarts,
    // and the pre-shuffle order while shuffled so un-shuffling restores it.
    unawaited(
      _store.write(
        AppConstants.queueShufflePersistKey,
        state.shuffleEnabled ? 1 : 0,
      ),
    );
    unawaited(
      _store.write(AppConstants.queueRepeatPersistKey, state.repeatMode.index),
    );
    if (state.shuffleEnabled) {
      unawaited(
        _store.write(
          AppConstants.queueOriginalPersistKey,
          _unshuffledTracks?.map((t) => t.id).whereType<int>().join(',') ?? '',
        ),
      );
    }
  }
}

/// Queue manager binding. [settingsStoreProvider] lives in the design-system
/// theme file (Task 2 owns it there); [queueTrackSourceProvider] is
/// overridden with a Drift-backed source in the composition root (Task 4).
final queueManagerProvider =
    StateNotifierProvider<QueueManager, QueueState>((ref) {
  return QueueManager(
    engine: ref.watch(playbackEngineProvider),
    store: ref.watch(settingsStoreProvider),
    trackSource: ref.watch(queueTrackSourceProvider),
  );
});
