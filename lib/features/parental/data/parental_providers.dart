import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/parental_dao.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';
import 'package:wavely/features/parental/data/track_filter.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

/// Persistence keys for the blocklists / switches that are NOT in Drift.
/// (Words, profiles and audit rows live in SQLite via [ParentalDao].)
const String kParentalEnabledKey = 'wavely.parental.enabled';
const String kParentalBlockNoLyricsKey = 'wavely.parental.blockNoLyrics';
const String kParentalBlockedArtistsKey = 'wavely.parental.blockedArtists';
const String kParentalBlockedAlbumsKey = 'wavely.parental.blockedAlbums';
const String kParentalBlockedGenresKey = 'wavely.parental.blockedGenres';
const String kParentalWhitelistKey = 'wavely.parental.whitelist';

/// Master switch for the whole parental-control feature. Default OFF —
/// filtering is opt-in; parents flip the switch on the Parental screen.
class ParentalStatus {
  const ParentalStatus({required this.enabled});

  final bool enabled;
}

/// Feature-scoped DAO handle (tests override [databaseProvider]).
final parentalDaoProvider = Provider<ParentalDao>(
  (ref) => ref.watch(databaseProvider).parentalDao,
);

/// Bumped after every parental write so the FutureProviders below re-read.
final parentalRefreshProvider = StateProvider<int>((ref) => 0);

/// Master enable flag, hydrated from the settings store.
final parentalStatusProvider = FutureProvider<ParentalStatus>((ref) async {
  ref.watch(parentalRefreshProvider);
  final store = ref.watch(settingsStoreProvider);
  final enabled = await store.read<bool>(kParentalEnabledKey) ?? false;
  return ParentalStatus(enabled: enabled);
});

/// Word matcher rebuilt whenever blocked words / whitelist change.
final wordMatcherProvider = FutureProvider<WordMatcher>((ref) async {
  ref.watch(parentalRefreshProvider);
  final dao = ref.watch(parentalDaoProvider);
  final store = ref.watch(settingsStoreProvider);
  final words = await dao.allWords();
  final whitelist = await store.read<List<String>>(kParentalWhitelistKey) ??
      const <String>[];
  return WordMatcher(words: words, whitelist: whitelist);
});

/// Composed filter: blocked words + no-lyrics policy (settings-store flag OR
/// the first profile's flag) + artist/album/genre blocklists.
final trackFilterProvider = FutureProvider<TrackFilter>((ref) async {
  ref.watch(parentalRefreshProvider);
  final dao = ref.watch(parentalDaoProvider);
  final store = ref.watch(settingsStoreProvider);

  final words = await dao.allWords();
  final profiles = await dao.allProfiles();
  final profileBlocks =
      profiles.isNotEmpty && profiles.first.blockNoLyrics;
  final storeBlocks = await store.read<bool>(kParentalBlockNoLyricsKey);
  final artists = await _readList(store, kParentalBlockedArtistsKey);
  final albums = await _readList(store, kParentalBlockedAlbumsKey);
  final genres = await _readList(store, kParentalBlockedGenresKey);

  return TrackFilter(
    words: words,
    blockNoLyrics: profileBlocks || (storeBlocks ?? false),
    blockedArtists: artists,
    blockedAlbums: albums,
    blockedGenres: genres,
  );
});

/// Raw blocked-word rows for the words editor section.
final blockedWordsProvider = FutureProvider<List<BlockedWordRow>>(
  (ref) async {
    ref.watch(parentalRefreshProvider);
    return ref.watch(parentalDaoProvider).allWords();
  },
);

/// Recent audit entries for the log section (newest first).
final parentalAuditProvider = FutureProvider<List<ParentalAuditRow>>(
  (ref) async {
    ref.watch(parentalRefreshProvider);
    return ref.watch(parentalDaoProvider).recentAudit(limit: 50);
  },
);

/// Local profiles for the Profiles section / PIN gate.
final parentalProfilesProvider = FutureProvider<List<LocalProfileRow>>(
  (ref) async {
    ref.watch(parentalRefreshProvider);
    return ref.watch(parentalDaoProvider).allProfiles();
  },
);

Future<List<String>> _readList(SettingsStore store, String key) async =>
    await store.read<List<String>>(key) ?? const <String>[];

// ---------------------------------------------------------------------------
// ORCHESTRATOR WIRING (queue_manager.dart is owned by the orchestrator —
// do NOT edit it from this agent; snippet below is the exact integration):
//
//   /// Wrap `_loadCurrent` so every track passes the parental filter before
//   /// the engine loads it. Import:
//   ///   package:wavely/features/parental/data/censor_executor.dart
//   ///   package:wavely/features/parental/data/censor_planner.dart
//   ///   package:wavely/features/parental/data/censor_service.dart
//   ///   package:wavely/features/parental/data/parental_providers.dart
//   ///   package:wavely/features/parental/data/track_filter.dart
//   Future<void> _loadCurrent(Track track) async {
//     final status = await ref.read(parentalStatusProvider.future);
//     if (!status.enabled) return _engineLoad(track.filePath);
//
//     final filter = await ref.read(trackFilterProvider.future);
//     final matcher = await ref.read(wordMatcherProvider.future);
//     final lyrics = await ref.read(trackLyricsProvider(track).future);
//     final verdict = await filter.evaluate(
//       track: track, lyrics: lyrics, matcher: matcher);
//     final dao = ref.read(parentalDaoProvider);
//     unawaited(dao.audit(
//       switch (verdict) {
//         TrackVerdict.blocked => 'track_blocked',
//         TrackVerdict.censorNeeded => 'track_censored',
//         TrackVerdict.allowed => 'track_allowed',
//       },
//       details: {'trackId': track.id, 'title': track.title},
//     ));
//
//     switch (verdict) {
//       case TrackVerdict.blocked:
//         return next(); // auto-skip; never load the original
//       case TrackVerdict.censorNeeded:
//         final plan = CensorPlanner.plan(lyrics: lyrics, matcher: matcher);
//         final service = CensorService(
//           executor: const FfmpegCensorExecutor(),
//           cacheDirProvider: () async => (await getTemporaryDirectory()).path,
//         );
//         final censored = await service.censorTrack(
//           track: track, plan: plan);
//         final path = censored.fold(
//           onErr: (_) => null, onSuccess: (p) => p);
//         // Policy: censored file when ready, otherwise fall back to the
//         // original — censoring must never block playback.
//         return _engineLoad(path ?? track.filePath);
//       case TrackVerdict.allowed:
//         return _engineLoad(track.filePath);
//     }
//   }
// ---------------------------------------------------------------------------
