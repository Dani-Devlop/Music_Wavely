import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/features/player/data/adaptive_accent.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

part 'adaptive_accent_service.g.dart';

/// Phase 10.1: watches the queue's current track and, when the adaptive
/// accent mode is enabled, extracts an accent from the album art and
/// publishes it into the settings (the theme provider resolves the seed).
///
/// Failures degrade silently — a broken cover must never repaint the app
/// or break playback.
@Riverpod(keepAlive: true)
class AdaptiveAccentService extends _$AdaptiveAccentService {
  /// Last cover the extraction ran against (dedupe track changes that
  /// share the same art).
  String? _lastCover;

  @override
  void build() {
    final manager = ref.watch(queueManagerProvider.notifier);
    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
      _lastCover = null;
    });
    _subscription = manager.stream.listen(_onQueueState);
    // The initial sync mutates settingsProvider — that must never happen
    // during provider initialization (Riverpod forbids it), so defer to a
    // microtask; live events keep flowing through the subscription.
    final initial = ref.read(queueManagerProvider);
    Future<void>.microtask(() => _onQueueState(initial));
  }

  StreamSubscription<void>? _subscription;

  void _onQueueState(QueueState state) {
    final track = state.currentTrack;
    final enabled = ref.read(settingsProvider).adaptiveAccent;
    final cover = track?.coverPath;
    if (!enabled) {
      // Disabled: clear the stored accent so the named palette wins.
      ref.read(settingsProvider.notifier).setAdaptiveAccentValue(0);
      _lastCover = null;
      return;
    }
    if (cover == null || cover.isEmpty || cover == _lastCover) {
      return;
    }
    _lastCover = cover;
    unawaited(_extract(cover));
  }

  Future<void> _extract(String cover) async {
    final accent = await AdaptiveAccentExtractor.fromFile(cover);
    // The settings write is a no-op when the user flipped the toggle off
    // meanwhile (setAdaptiveAccentValue guards).
    ref.read(settingsProvider.notifier).setAdaptiveAccentValue(
          accent?.toARGB32() ?? 0,
        );
  }
}
