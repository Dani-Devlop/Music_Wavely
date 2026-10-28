import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/repositories/drift_lyrics_cache.dart';
import 'package:wavely/data/repositories/drift_queue_track_source.dart';
import 'package:wavely/data/repositories/play_recorder.dart';
import 'package:wavely/data/repositories/queue_track_launcher.dart';
import 'package:wavely/data/repositories/shared_prefs_settings_store.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/lyrics/domain/lrc_parser.dart';
import 'package:wavely/features/parental/data/censor_executor.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';
import 'package:wavely/features/parental/data/censor_service.dart';
import 'package:wavely/features/parental/data/no_lyrics_policy.dart';
import 'package:wavely/features/parental/data/parental_providers.dart';
import 'package:wavely/features/parental/data/track_filter.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/shuffle/advanced_shuffle.dart';
import 'package:wavely/app/root_messenger.dart';

/// Composition root: builds the provider override list for a real app run.
///
/// Wiring map (what overrides what):
/// - [databaseProvider] → the [AppDatabase] created in bootstrap (`Value`
///   override so bootstrap owns the database lifecycle).
/// - [sharedPrefsProvider] → the bootstrap [SharedPreferences] instance
///   (the canonical [SettingsNotifier] reads its keys through it).
/// - [settingsStoreProvider] → [SharedPreferencesSettingsStore] over the
///   bootstrap `SharedPreferences` instance (queue persistence + legacy
///   theme/scan-folder keys).
/// - [lyricsCacheProvider] → [DriftLyricsCache] over `db.lyricsDao` (the
///   default was a no-op cache).
/// - [queueTrackSourceProvider] → [DriftQueueTrackSource] over
///   `db.tracksDao` (the default resolved to nothing, making `restore()`
///   a no-op).
/// - [queueManagerProvider] → [QueueManager] with the play-recording hook:
///   every track that actually starts playing is written to the `plays`
///   table through [playRecorderProvider].
/// - [trackLauncherProvider] → [QueueTrackLauncher] bound to the live
///   [queueManagerProvider] (the default threw). The launcher provider
///   watches the queue manager inside the same override scope — that is
///   fine because both providers live in one container.
///
/// Deliberately NOT overridden here:
/// - [playbackEngineProvider]: the platform conditional import picks the
///   right real engine; only tests override it with a fake.
List<Override> buildOverrides({
  required AppDatabase db,
  required SharedPreferences prefs,
}) =>
    <Override>[
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      settingsStoreProvider.overrideWith(
        (ref) => SharedPreferencesSettingsStore(prefs),
      ),
      lyricsCacheProvider.overrideWith(
        (ref) => DriftLyricsCache(db.lyricsDao),
      ),
      queueTrackSourceProvider.overrideWith(
        (ref) => DriftQueueTrackSource(db.tracksDao),
      ),
      queueManagerProvider.overrideWith(
        (ref) => QueueManager(
          engine: ref.watch(playbackEngineProvider),
          store: ref.watch(settingsStoreProvider),
          trackSource: ref.watch(queueTrackSourceProvider),
          onTrackStarted: (track) =>
              unawaited(ref.read(playRecorderProvider).record(track)),
          advancedShuffleConfig: ref.watch(advancedShuffleConfigProvider),
          trackPreloadHook: (track) => _parentalPreload(ref, track),
        ),
      ),
      trackLauncherProvider.overrideWith(
        (ref) => QueueTrackLauncher(ref.watch(queueManagerProvider.notifier)),
      ),
      advancedShuffleConfigProvider.overrideWith(
        (ref) => ShuffleConfigNotifier(ref.watch(sharedPrefsProvider)),
      ),
    ];

/// Parental-control preload adapter (Stage 1.2, B8): maps the feature's
/// providers onto [TrackLoadDecision]. Failures degrade to `null` (allow) —
/// a broken censor pipeline must never brick playback.
Future<TrackLoadDecision?> _parentalPreload(Ref ref, Track track) async {
  final status = await ref.read(parentalStatusProvider.future);
  if (!status.enabled) {
    return null;
  }
  final filter = await ref.read(trackFilterProvider.future);
  final matcher = await ref.read(wordMatcherProvider.future);
  final trackId = track.id;
  var lyrics = const LyricsResult(lines: <LyricLine>[]);
  if (trackId != null) {
    final row = await ref.watch(databaseProvider).lyricsDao
        .get(trackId: trackId);
    if (row != null) {
      lyrics = LrcParser.parse(row.syncedLrc ?? row.plainText ?? '');
    }
  }
  final verdict =
      await filter.evaluate(track: track, lyrics: lyrics, matcher: matcher);
  switch (verdict) {
    case TrackVerdict.blocked:
      return const TrackLoadDecision.skip();
    case TrackVerdict.censorNeeded:
      final plan = CensorPlanner.plan(lyrics: lyrics, matcher: matcher);
      if (!plan.hasPlan) {
        // Stage 3 final polish (BUG-9): an explicit track whose lyrics are
        // unsynced cannot be censored — the configured policy decides. The
        // legacy "play uncensored + audit" behavior is now `allow` only;
        // the DEFAULT is `block` (skip + toast). The bypass stays audited.
        unawaited(
          ref.watch(databaseProvider).parentalDao.audit(
                'censor_skipped_no_synced_lyrics',
                details: <String, Object?>{
                  'trackId': trackId,
                  'title': track.title,
                  'policy': 'noLyricsPolicy',
                },
              ),
        );
        return _censorFallbackDecision(
          await ref.read(noLyricsPolicyProvider.future),
          track,
          reason: 'no synced lyrics',
        );
      }
      final service = CensorService(
        executor: const FfmpegCensorExecutor(),
        cacheDirProvider: () async =>
            (await getTemporaryDirectory()).path,
      );
      final rendered = await service.censorTrack(track: track, plan: plan);
      final path = rendered.fold(
        onSuccess: (value) => value,
        onErr: (_) => null,
      );
      if (path == null) {
        // Stage 3 final polish (BUG-9): the ffmpeg render failed — the
        // configured policy decides (was: always play the uncensored
        // original with an audit trail, SEC-6).
        unawaited(
          ref.watch(databaseProvider).parentalDao.audit(
                'censor_render_failed',
                details: <String, Object?>{
                  'trackId': trackId,
                  'title': track.title,
                  'policy': 'noLyricsPolicy',
                },
              ),
        );
        return _censorFallbackDecision(
          await ref.read(noLyricsPolicyProvider.future),
          track,
          reason: 'censor render failed',
        );
      }
      return TrackLoadDecision.replace(path);
    case TrackVerdict.allowed:
      return null;
  }
}

/// BUG-9: applies the parental censor-fallback policy when censoring is
/// impossible. `block` skips with a UI toast, `mute` plays silently, and
/// only the explicit `allow` choice plays the uncensored original.
TrackLoadDecision? _censorFallbackDecision(
  NoLyricsPolicy policy,
  Track track, {
  required String reason,
}) {
  switch (policy) {
    case NoLyricsPolicy.block:
      showRootSnackBar(
        'Skipped "${track.title}" — explicit track, censoring unavailable '
        '($reason).',
      );
      return const TrackLoadDecision.skip();
    case NoLyricsPolicy.mute:
      showRootSnackBar(
        'Playing "${track.title}" muted — explicit track, censoring '
        'unavailable ($reason).',
      );
      return const TrackLoadDecision.muted();
    case NoLyricsPolicy.allow:
      return null; // explicit parental choice: play the uncensored original
  }
}
