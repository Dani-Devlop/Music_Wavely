import 'dart:async';

import 'package:home_widget/home_widget.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

part 'widget_sync.g.dart';

/// Data keys published into the home-widget storage
/// (Android SharedPreferences file `HomeWidgetPreferences`, written by the
/// `home_widget` plugin — the widget providers and the quick-settings tile
/// read the same keys natively).
abstract final class WidgetDataKeys {
  /// Current track title (empty when idle).
  static const String title = 'wavely_title';

  /// Current artist (empty when idle).
  static const String artist = 'wavely_artist';

  /// Current album (empty when unknown).
  static const String album = 'wavely_album';

  /// Absolute cover file path (empty when the track has no art).
  static const String coverPath = 'wavely_cover';

  /// `'1'` while playing, `'0'` otherwise (widgets + QS tile state).
  static const String playing = 'wavely_playing';

  /// Track position in milliseconds (best-effort, pushed with track/state
  /// changes — the widgets do NOT tick the seekbar).
  static const String positionMs = 'wavely_position_ms';

  /// Track duration in milliseconds.
  static const String durationMs = 'wavely_duration_ms';

  /// Monotonic epoch of the last data push (widgets compare it to decide
  /// whether a rebuild is actually needed).
  static const String updatedAt = 'wavely_updated_at';
}

/// Qualified Android class names of the three home widgets; the Dart side
/// triggers `AppWidgetManager` updates through them.
abstract final class WavelyWidgets {
  /// 4×1 simple widget (track title + artist).
  static const String small = 'WavelyWidgetSmall';

  /// 4×1 widget with playback controls.
  static const String controls = 'WavelyWidgetControls';

  /// 3×4 widget with album art.
  static const String large = 'WavelyWidgetLarge';
}

/// Publishes queue/playback state to the Android home-screen widgets and
/// the quick-settings tile (Phase 9.2 / 9.3).
///
/// Subscribes to the [QueueManager] state stream and pushes a compact
/// snapshot into `home_widget` storage whenever the meaningful part changes
/// (track identity, playing state, duration) — position ticks do NOT
/// trigger widget rebuilds. Every platform interaction is wrapped in
/// try/catch: widgets are an enhancement, never a playback dependency.
@Riverpod(keepAlive: true)
class WidgetSync extends _$WidgetSync {
  StreamSubscription<QueueState>? _subscription;

  /// Signature of the last pushed snapshot (dedupe for the stream's
  /// position ticks).
  String? _lastSignature;

  /// Serializes pushes so the widgets always converge on the LATEST
  /// snapshot (rapid state changes must never interleave writes). Drain
  /// this future in tests to wait for a fully-pushed state.
  @visibleForTesting
  Future<void> pushChain = Future<void>.value();

  /// Test seam: `true` forces the Android code path on any host platform
  /// (the generated provider passes null → [PlatformUtils.isAndroid]).
  @visibleForTesting
  WidgetSync({bool? forceAndroidTarget})
      : _forceAndroidTarget = forceAndroidTarget;

  final bool? _forceAndroidTarget;

  bool get _androidTarget => _forceAndroidTarget ?? PlatformUtils.isAndroid;

  @override
  void build() {
    // Android-only: home_widget channel exists on mobile; the widgets and
    // the tile are Android-only surfaces anyway.
    if (!_androidTarget) {
      return;
    }
    // Watch the NOTIFIER only (its instance never changes): watching the
    // queue STATE would rebuild this provider on every position tick. The
    // initial snapshot comes from a read; later snapshots flow through the
    // stream subscription below.
    final initial = ref.read(queueManagerProvider);
    final manager = ref.watch(queueManagerProvider.notifier);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });
    _subscription = manager.stream.listen(_onQueueState);
    _onQueueState(initial);
  }

  void _onQueueState(QueueState state) {
    final track = state.currentTrack;
    final signature = <String>[
      track?.id?.toString() ?? '-',
      track?.sourceTrackId ?? '-',
      state.playbackState.name,
      track?.title ?? '',
      track?.artistOrUnknown ?? '',
      track?.coverPath ?? '',
    ].join('|');
    if (signature == _lastSignature) {
      return;
    }
    _lastSignature = signature;
    pushChain = pushChain.then((_) => _push(state, track));
  }

  Future<void> _push(QueueState state, Track? track) async {
    try {
      final playing = state.playbackState == PlaybackState.playing;
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.title,
        track?.title ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.artist,
        track?.artistOrUnknown ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.album,
        track?.album ?? '',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.coverPath,
        (track?.coverPath != null && track!.coverPath!.isNotEmpty)
            ? track.coverPath!
            : '',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.playing,
        playing ? '1' : '0',
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.positionMs,
        state.position.inMilliseconds.toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.durationMs,
        (track?.durationMs ?? 0).toString(),
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetDataKeys.updatedAt,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      for (final widget in const <String>[
        WavelyWidgets.small,
        WavelyWidgets.controls,
        WavelyWidgets.large,
      ]) {
        await HomeWidget.updateWidget(androidName: widget);
      }
    } on Object {
      // Platform channel unavailable (tests / desktop / widget manager
      // missing) — widgets stay stale, playback is unaffected.
    }
  }
}
