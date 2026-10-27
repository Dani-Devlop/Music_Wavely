# Stage 1.2 — Stage Report (auth, sync, AI, parental, analytics, discovery)

**Status: AUTHORED, AWAITING LOCAL VERIFICATION.** No Flutter/Dart SDK exists
in the authoring sandbox; nothing has been compiled or run. All claims below
are about what EXISTS in the tree, verified by scripted import/structure
checks (0 unresolved `package:wavely/` imports across 209 lib files +
74 test files). Section 5 lists exactly what the owner must run.

## 1. What was built

- **B0 Precondition** — `docs/STAGE_1_2_PRECONDITION.md`: Stage 1.1
  abstractions confirmed, every touched provider/DAO/use-case signature
  listed, folder structure verified.
- **B1 Metadata sources** — `docs/METADATA_SOURCES.md` with LIVE-verified
  endpoints (MusicBrainz artist+release-groups ✅, Deezer search ✅ /
  related denied-from-sandbox-IP (graceful degradation documented),
  Wikipedia ✅, archive.org ✅, NME RSS ✅, Pitchfork RSS 301→200 ✅,
  Reddit returns an HTML bot-page here (client validates JSON and degrades),
  Jamendo **requires** client_id — live error code 5).
  Implementation: `lib/data/remote/metadata_http.dart` (UA, RateLimiter,
  CachingHttpClient over Drift `http_cache` with stale-while-error), one
  client per source (MB, Deezer, Wikipedia, archive.org, Reddit, RSS/news).
- **B2 Supabase** — `supabase/config.toml`,
  `supabase/migrations/0001_init.sql` (9 tables, RLS everywhere, user →
  profiles/settings trigger, `redeem_telegram_session` RPC,
  `telegram_links`), edge functions `telegram-auth` + `telegram-webhook`
  (Deno, secret-validated, /start token flow, Stage 2.2 stubs),
  `docs/SUPABASE_SETUP.md`.
- **B3 Auth** — `supabase_client_provider`, `AuthRepository` (email
  in/out, session stream, guarded delete), `TelegramAuthService`
  (uuid token → secure storage → t.me deep link → 2 s polling ≤5 min →
  verifyOtp), 4 screens (welcome/login/signup/telegram) with graceful
  "disabled" states when Supabase is unconfigured, `auth_guard.dart`
  (`/ai-chat` protected; library+playback never require an account) wired
  into the router.
- **B4 Sync** — Drift `sync_outbox` + `SyncOutboxDao` (max 5 attempts,
  parked failures), `SyncBackend` interface + `SupabaseSyncBackend`,
  `SyncService` (start/resume/regain/5-min timer, `Stream<SyncStatus>`,
  push+pull, remote-play dedupe by fingerprint+startedAt, unmatched remote
  plays skipped honestly), `ConflictResolver` (settings LWW, playlists
  keep-both), `fingerprint.dart` (sha1 of source/sourceTrackId/title/artist),
  `PlaysSync` outbox hook, `SyncStatusView` widget; engine started once from
  `MainShell.initState`.
- **B5 Analytics** — `AnalyticsRepository` (per-period totals, top
  tracks/artists/genres, skip rate with documented 30 s threshold,
  lifetime favorites, On Repeat ≥3×/7d, Top-of-year, daily aggregate
  outbox batch to `track_stats_daily`), `AnalyticsScreen` (chips, hero
  time, top lists, fl_chart genre bars), `LifetimeFavoritesScreen` (top 50),
  `replay_rows.dart` (On Repeat + Your Top {year} widgets for Library).
- **B6 AI chat** — `AiProvider` abstraction + Gemini 2.0-flash (primary)
  / GPT-4o-mini (fallback) / disabled (no key) factory, tool schemas
  (search_library, build_queue, create_playlist, get_listening_stats),
  `AiToolExecutor` (fabricated ids REJECTED — only DB-verified ids reach the
  queue), `MoodClassifier` (8 moods; heartbreak excludes romantic/love,
  prefers uplifting/empowerment/growth/discipline, en), `AiService` (tool
  loop ≤4 turns, 10 req/min sliding window, 5-min identical-prompt cache),
  privacy-bounded `LibrarySnapshot` (≤500 tracks, no paths/PII),
  `AiChatScreen` (mood chips, markdown, Play all/regenerate/cancel, honest
  disabled state).
- **B7 Advanced shuffle** — `ShuffleConfig` (language/genre/artist allow+
  block, explicit, weighting 0–1, no-repeat window, seed) + `AdvancedShuffle`
  pipeline (filter → weighted seeded order → anchor current → no-repeat
  window), persisted JSON config provider, `ShuffleConfigSheet`, and
  `QueueManager.toggleShuffle` integration (advanced when configured,
  BasicShuffle otherwise — Stage 1.1 behavior untouched by default).
- **B8 Parental** — `WordMatcher` (whole-word, leet/space/hyphen
  obfuscations, whitelist), `CensorPlanner` (line-level mute ranges from
  synced lyrics, no-timestamps → "no plan"), `CensorService` +
  conditional-export ffmpeg trio (`ffmpeg_kit_flutter_new`, beep policy,
  cache `<trackId>.censored.m4a`, web-stub), `TrackFilter`
  (allowed/blocked/censorNeeded incl. no-lyrics policy), `ParentalDao`
  tables (blocked_words, profiles_local, parental_audit), PIN-gated
  `ParentalScreen` (profiles, word editor + CSV import, artist/album/genre
  blocks, audit log), and the `QueueManager.trackPreloadHook` integration
  (blocked → cyclic skip bounded by one pass; censor → cached render else
  original; hook failures degrade to allow).
- **B9 Onboarding** — 10-page wizard (privacy, theme w/ live preview,
  region via ipapi with locale fallback, language priority reorder +
  never-play, download quality for 2.1, storage template, parental opt-in +
  PIN + seed words, AI consent, folders via scanner, done) persisting
  through the canonical settings notifier + `OnboardingRepository`
  (`wavely.onboarding.*`) and the `wavely.onboarding.completed` flag with a
  router redirect (first-run forced, later skipped).
- **B10 Discovery** — `DiscoveryService` (new-from-followed via MB
  since followedAt−30d; because-you-listen-to via Deezer /related off top-3
  played artists, excluding followed; new-this-week among top artists; 6 h
  caches), `DiscoveryScreen` (3 sections, pull-to-refresh, offline empty
  states), `follow_artist.dart` (+ArtistFollowsDao idempotent follow),
  optional Spotify PKCE metadata adapter strictly behind
  `SPOTIFY_CLIENT_ID` with the redirect-host TODO documented.
- **Foundation (orchestrator)** — pubspec deps (versions live-verified),
  compile-time env (`WavelyEnv`, `--dart-define-from-file=.env`; dotenv
  REJECTED because it requires a build-time `.env` asset), Drift schema v2
  (6 new tables, 4 new DAOs, `Migration0002`), router with 10 new routes +
  onboarding/auth redirects, composition-root wiring (shuffle config,
  parental preload hook, sync start), settings "More" section rows.

## 2. File inventory

New since Stage 1.1 (excl. regenerated support): **74 new lib files +
20 new test files** (plus 2 Wave-1 test files already counted), ~3,300 test
lines. Key trees: `lib/data/remote/` (metadata clients), `lib/data/sync/`,
`lib/features/{auth,ai_chat,parental,analytics,discovery,onboarding,sync}/`,
`lib/playback/shuffle/advanced_shuffle.dart`,
`supabase/{config.toml,migrations,functions/}`,
`docs/{STAGE_1_2_PRECONDITION,METADATA_SOURCES,SUPABASE_SETUP}.md`.
Modified: `pubspec.yaml`, `lib/app/{router,main_shell,providers}.dart`,
`lib/data/local/db/app_database.dart`, settings screen (More section),
`.env.example`.

## 3. Tests authored (all *authored, awaiting local run*)

74 test files total / 12,408 lines. Stage 1.2 additions: metadata client
contract tests (UA, cache write/read, TTL, stale-while-error), rate limiter,
RSS/Atom parser, discovery service (period filter, MBID resolution,
dedupe/exclusion, failure degradation) + screen (offline, empty), auth repo
(against `AuthApi` seam), Telegram service (success/timeout/launch-failure
with injectable clock), auth guard table test, 4 auth screen tests, sync
service (push/remove, retry park, pull dedupe/skip, connectivity regain),
payload mappers, conflict resolver (LWW + keep-both), fingerprint,
analytics repository (100-play seed across periods, skip-rate math,
on-repeat, top-of-year) + screen, mood classifier (20+ sentences incl. the
spec breakup case), AI service (fabricated ids rejected, maxTurns,
rate limit, cache), providers (retry/backoff/parse), library snapshot
(500 cap, no PII), AI chat screen, word matcher (15 cases), censor planner
(5), censor service (cache/failure), track filter matrix, parental screen
(PIN gate), advanced shuffle (8 fixed-seed scenarios + anchor/no-repeat),
shuffle config JSON, onboarding repository + walkthrough + persistence.

## 4. Verification status (honest)

| Item | Status |
|---|---|
| Import graph (lib+test) | ✅ scripted: 0 unresolved |
| Migration/DAO structure | ✅ file-audited; generated parts pending build_runner |
| Endpoints | ✅ live-verified 2026-10-27 (see docs/METADATA_SOURCES.md) |
| Compile / analyze / tests | ❌ NOT run — no SDK in sandbox |
| Supabase SQL / edge functions | ❌ NOT run — owner: `supabase db reset` |
| ffmpeg censor rendering | ❌ NOT run — device-only plugin |

## 5. Local verification (owner)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --update-goldens test/design_system   # seed goldens once
flutter test --coverage
supabase init && supabase db reset                 # optional: backend
supabase functions serve telegram-auth             # optional
flutter run --dart-define-from-file=.env           # full features
```

## 6. Known limitations

1. Heartbreak mood exclusions reach the model via system prompt only; hard
   genre enforcement at queue-build time is a follow-up.
2. Telegram flow uses magic-link `token_hash` + `verifyOtp` (no direct JWT
   minting in supabase-js admin API) — documented in the edge function.
3. Deezer `/related` was Access-Denied from the authoring sandbox IP
   (search works); section degrades gracefully.
4. Reddit may return an HTML bot page depending on network — client
   validates content-type and degrades.
5. PIN hash is plain sha256 (documented weakness; salted upgrade = security
   pass). Whitelist has matcher+provider plumbing but no editor UI.
6. Remote plays that do not match a local track are skipped on pull (no
   orphan rows) — cross-device full history needs the accounts layer.
7. `setSpeed` remains state-only (engine contract unchanged since 1.1).
8. Multi-tool-call turns replay one tool_call_id on the OpenAI path.
9. Spotify PKCE cannot complete until the deep-link host is registered.

## 7. Blockers

None for authoring. Owner-side: SDK required (§5); Supabase/Telegram keys
optional (all features degrade); first `build_runner` run generates all
`*.g.dart`/`*.freezed.dart` parts (expected "part not found" before it).

## 8. TODOs remaining in lib/ (all documented in-code)

- `spotify_metadata_adapter.dart` ×2 — app-link host registration required.
- `gemini_provider.dart` / `openai_provider.dart` — confirm response shapes
  on first live run.
- `pin_hash.dart` — salted-hash upgrade (security pass).

## 9. Post-merge

Owner opens PR `main...feat/stage-1.2`, reviews, merges. Then **revoke the
session's GitHub token** (see the security reminder printed after the push).
