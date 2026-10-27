# Stage 1.2 — Precondition document (B0)

Written BEFORE any Stage 1.2 feature code. Confirms the Stage 1.1 surface
Stage 1.2 builds on and lists every provider/DAO/use case it touches.

## 1. Stage 1.1 abstractions — intact

| Abstraction | File | Stage 1.2 use |
|---|---|---|
| `SourceProvider` | `lib/domain/repositories/source_provider.dart` | untouched (online sources are Stage 2.1) |
| `PlaybackEngine` | `lib/playback/engines/playback_engine.dart` | untouched contract (setSpeed stays state-level) |
| `LyricsProvider` | `lib/domain/repositories/lyrics_provider.dart` | reused by parental no-lyrics policy |
| `Result` / `Failure` | `lib/core/errors/` | every Stage 1.2 client returns `Result<T>` |
| Entities | `lib/domain/entities/` | `Track`, `Artist`, `Album`, `PlayEvent`, `LyricsResult` reused as-is |
| `SettingsStore` | `lib/core/settings/settings_store.dart` | sync settings mirror |
| `LibraryScanner` | `lib/features/library/data/library_scanner.dart` | untouched |
| Design system | `lib/design_system/` | GlassCard / tokens reused in all new screens |
| Composition root | `lib/app/providers.dart` (`buildOverrides`) | new Stage 1.2 bindings appended here |

## 2. Providers / DAOs / use cases Stage 1.2 touches (exact signatures)

```dart
// Drift DAOs (lib/data/local/db/daos/)
Future<List<Track>> TracksDao.getAll({required int limit, required int offset, String orderBy});
Future<Track> TracksDao.upsertBySource(TracksCompanion entry);
Future<List<Track>> TracksDao.byIds(List<int> ids);
Future<List<Track>> TracksDao.searchFts(String query);
Future<int> PlaysDao.insertPlay(PlaysCompanion entry);
Future<List<PlayRow>> PlaysDao.playsForTrack(int trackId);
Future<int> PlaysDao.totalListenedMs();
Future<List<Track>> PlaysDao.topTracks({int limit});
Future<LyricsCacheRow?> LyricsDao.get({required int trackId, String? provider});
// Stage 1.2 DAOs (added with this precondition):
Future<String?> HttpCacheDao.get(String requestKey);
Future<void> HttpCacheDao.put({required String requestKey, required String body, required int statusCode, required DateTime expiresAt});
Future<int> SyncOutboxDao.enqueue({required String tableName, required String rowKey, required String op, required String payload});
Future<List<SyncOutboxRow>> SyncOutboxDao.pending({int limit});
Future<int> SyncOutboxDao.count();
Future<void> ParentalDao.audit(String event, {Map<String, Object?> details});
Future<List<BlockedWordRow>> ParentalDao.allWords();
Future<void> ArtistFollowsDao.follow(String artistName, {String? mbid});
Future<bool> ArtistFollowsDao.isFollowing(String artistName);
```

```dart
// Riverpod (lib/app/, lib/features/)
final databaseProvider           Provider<AppDatabase>       // memory-overridable
final sharedPrefsProvider        @Riverpod SharedPreferences // bootstrap override
final settingsProvider           NotifierProvider<SettingsNotifier, AppSettings>
final queueManagerProvider       StateNotifierProvider<QueueManager, QueueState>
final playbackEngineProvider     Provider<PlaybackEngine>    // tests override w/ FakePlaybackEngine
final lyricsRepositoryProvider   Provider<LyricsRepository>
final trackLauncherProvider      Provider<TrackLauncher>     // QueueTrackLauncher
final libraryScannerProvider     Provider<LibraryScanner>    // conditional io/web arms
```

```dart
// QueueManager surface used by sync/analytics/parental integration
Future<void> setQueue(List<Track> tracks, {int startIndex = 0});
Future<void> play(); Future<void> pause(); Future<void> next(); Future<void> previous();
Future<void> toggleShuffle(); void setRepeatMode(RepeatMode mode);
final void Function(Track track)? onTrackStarted; // play history hook
```

## 3. Folder structure (Master Context §3) — confirmed

```
lib/
  app/            bootstrap, router, shell, providers, theme
  core/           constants, errors, extensions, settings, utils, config/env
  data/
    local/db/     tables/, daos/, migrations/, mappers/
    remote/       (Stage 1.2: metadata_clients/, supabase_client_provider.dart)
    repositories/ drift-backed implementations
    sync/         (Stage 1.2: sync_service.dart, conflict_resolver.dart, plays_sync.dart)
  design_system/  components/, themes/, tokens/
  domain/         entities/, repositories/, usecases/
  features/       library/, lyrics/, player/, search/, settings/,
                  (Stage 1.2 additions: auth/, sync/, analytics/, ai_chat/,
                   parental/, onboarding/, discovery/)
  playback/       engines/, queue/, shuffle/
```

## 4. Non-goals carried from Master Context

- No online playback sources (Stage 2.1). Metadata APIs only.
- Spotify = metadata only, OAuth2 PKCE adapter behind SPOTIFY_CLIENT_ID.
- No fabricated verification: everything authored, awaiting local run.

## 5. New Stage 1.2 dependencies (versions verified live on pub.dev 2026-10-27)

supabase_flutter ^2.18.3 · fl_chart ^1.3.0 · uuid ^4.6.0 · crypto ^3.0.8 ·
http ^1.6.0 · flutter_markdown ^0.7.7+1 · ffmpeg_kit_flutter_new ^4.6.7 ·
url_launcher ^6.3.3 (already landed in Phase A)

Env strategy: `--dart-define-from-file=.env` (no asset, no build-time file
requirement) — see `lib/core/config/env.dart`.
