# Stage 2.2 Report — News, Telegram Mini App, PWA, Desktop Packaging

Status: **authored, awaiting local run.** No Flutter SDK exists in this
sandbox; `flutter pub get`, `build_runner`, `flutter analyze` and
`flutter test` have never been executed against this tree. Everything
below was verified structurally (import resolution, YAML/JSON validity,
additive-only diff audit) — see the validation section.

Branch: `feat/stage-2.2` (PR against `main` @ `e27cfd0`).

## 1. What was built

### News (`lib/features/news/`)

- **Drift layer**: `tables/news_articles.dart` (UNIQUE `(source,
  sourceId)` index, ISO8601 text timestamps, JSON categories column),
  `migrations/0004_news.dart` (3→4, additive createTable),
  `daos/news_dao.dart` (batch upsert on the unique target, fault-tolerant
  reads, `NewsCategoryCodec`). `app_database.dart` registered additively
  (schemaVersion 4, `from < 4` hook).
- **`data/news_category.dart`** — 5-category taxonomy + word-boundary
  keyword classifier (`tech_ai`, `education`, `production`,
  `new_releases`, default `artist_news`). Pure Dart, 15-case test.
- **`data/news_service.dart`** — Reddit JSON (`r/Music`, `r/hiphopheads`,
  `r/indieheads`, UA `Wavely/1.0 (repo url)`), Pitchfork RSS, NME RSS +
  user custom RSS. Per-host `RateLimiter` (1 req/s), responses via the
  existing `CachingHttpClient` (`http_cache`, 30-min TTL, stale-while-
  error), classified on arrival, deduped by `(source, sourceId)`,
  persisted for offline. `getArticles` NEVER throws; a dead feed plus
  stored rows still serves articles. Pull-to-refresh honors the cache
  (the discovery screen's offline-first convention).
- **`presentation/news_screen.dart`** — multi-select category chips
  (persisted), article cards (`cached_network_image` + error/placeholder
  fallbacks, source + relative time + category labels), pull-to-refresh,
  tap → existing `LinkLauncher`, empty state with settings CTA,
  error/loaded/loading states.
- **`presentation/news_settings_screen.dart`** — category toggles,
  custom RSS add (validated: `Uri.tryParse` + scheme http/https only),
  feed removal, muted sources with unmute.
- **Integration (additive only)**: `/news` + `/news/settings` routes
  (mirrors the downloads route pair); Settings "More" gains a News row;
  Discovery appends a "News for you" section (top-5, selected categories)
  that **omits itself silently on any failure** — the existing discovery
  widget-test assertions (EmptyState counts) stay untouched.

### Telegram Mini App (`lib/features/telegram/`)

- **`telegram_web_app.dart`** — `dart:js_interop` extension-type bindings
  over `Telegram.WebApp` (`ready/expand/close/themeParams/initData/
  initDataUnsafe/MainButton/BackButton/HapticFeedback`), web-only by
  construction (imported solely from the web bridge arm).
- **`telegram_bridge.dart`** + `_web.dart` + `_stub.dart` — conditional-
  export seam (repo `engine_factory` pattern): `snapshot()` returns
  `{isInTelegram, initData, themeParams, user}`; the io stub is always
  not-in-Telegram; the web arm JSON-stringifies the JS objects.
- **`telegram_bridge_provider.dart`** — `telegramBridgeProvider` +
  `telegramStateProvider` + the compile-time `kTelegramMode` flag.
- **`telegram_auth_service.dart`** — POSTs the RAW `initData` to the
  edge function, maps the documented error contract to
  `TelegramAuthException` codes (`invalid_signature`, `expired`,
  `rejected`, `network`, `malformed_response`), applies the returned
  session through an injectable `TelegramSessionApplier` (production:
  `supabase.auth.setSession`). The client NEVER validates initData and
  NEVER derives identity from it (test-asserted).
- **`telegram_theme_adapter.dart`** — `themeParams` → Wavely token roles
  with defaults/fallbacks + a manual override pref.
- **`supabase/functions/telegram-webapp-auth/index.ts`** — Deno edge
  function: URLSearchParams parse, `data_check_string` sorted join,
  `secret = HMAC_SHA256(bot_token, "WebAppData")` via `crypto.subtle`,
  **timing-safe** hex comparison, `auth_date` ≤ 1 h, deterministic
  find-or-create (`<id>@telegram.wavely.app` + secret-derived password),
  sign-in → session JWT. Never logs `initData` or the token; coarse
  error messages (no validation oracle). Deploy command documented in
  `docs/TELEGRAM_MINIAPP.md`.
- **Bootstrap (additive)**: `kTelegramMode`
  (`--dart-define=TELEGRAM_MODE=true`) triggers `ready()`/`expand()` via
  the bridge after `runApp` — a guarded, web-only no-op elsewhere.
  `web/index.html` loads `telegram-web-app.js`.

### PWA (`web/` + `lib/features/web/`)

- **`web/manifest.json`** — full icon set (48→512), standalone,
  `#0A0E14`/`#7C5CFF`.
- **`web/icons/`** — 8 generated placeholder PNGs (PIL: `#7C5CFF` +
  white waveform). Owner replaces before release (documented).
- **`web/index.html`** — standard Flutter 3.35 template + manifest link,
  `theme-color`, `apple-touch-icon`, Telegram script, inline
  service-worker registration. (The repo had no `web/` — flutter create
  overlay model — so this is created, not edited.)
- **`web/service_worker.js`** — shell precache (per-asset tolerant
  install), SWR runtime cache for metadata hosts (lrclib, deezer,
  musicbrainz, jamendo, archive.org) with a 30-min window, **audio
  streams/downloads/Range endpoints never cached**, old-cache cleanup.
- **`pwa_media_session.dart`** — Media Session API wiring (play/pause/
  prev/next handlers + `MediaMetadata`), callback-injected so the class
  has no engine import; every JS touchpoint guarded. Wired from
  `playback_engine_web.dart` (the web factory arm) using additive
  `currentTrack`/`currentIndex` getters on `WebPlaybackEngine`.
- **`ios_guidance_banner.dart`** (+ conditional `_web`/`_stub` probe) —
  iOS+standalone detection, first-playback trigger, dismissible
  MaterialBanner pointing at the Telegram Mini App (`t.me/<bot>?startapp`
  from `WavelyEnv`), dismissal persisted. Wired additively from
  `MainShell.initState`; a complete no-op off web/iOS (existing shell
  tests unaffected). Pure gate logic in `IosGuidanceGate` (unit-tested).
- **`docs/KNOWN_LIMITATIONS_FINAL.md`** appended (§13–19): iOS PWA
  background audio, no remote download on web, browser codec variance,
  no local scan on web, Mini App background audio, placeholder icons,
  unsigned MSIX.

### Desktop packaging

- **`msix_config.yaml`** — `app.wavely.music`, `CN=Dani-Devlop`,
  `sign: false`; owner actions documented in `docs/PACKAGING.md` §3.
- **`flatpak/app.wavely.music.yml`** + **`.desktop`** — Freedesktop
  23.08, network/pulse/home/dri/wayland/x11 finish-args, CI-tarball
  wrapper module.
- **`lib/features/settings/data/update_service.dart`** (+ conditional
  `update_platform.dart` seam replacing `dart:io` on web) — GitHub
  Releases check (`releases/latest`), numeric-aware version compare,
  platform asset pick (`.msix`/`.AppImage`/`.apk`/`.dmg`), injectable
  `UpdateInstaller`; failures degrade to "up to date" honestly. Settings
  "Check for updates" row reports via SnackBar + opens the release page
  through `LinkLauncher`.
- **pubspec**: `auto_updater: ^1.0.0` (pub.dev-verified latest),
  dev-dep `flutter_distributor: ^0.6.10` (pub.dev-verified latest).
- **`.github/workflows/release.yml`** — tag `v*.*.*` (+ manual):
  android APK, windows zip + unsigned MSIX (fails soft), linux tarball +
  AppImage attempt (fails soft), `gh release create` job. No signing
  secrets anywhere.

## 2. File inventory

New lib files (23):

- `lib/features/news/data/{news_category,news_article,news_service,news_prefs,news_providers}.dart`
- `lib/features/news/presentation/{news_screen,news_settings_screen}.dart`
- `lib/features/telegram/{telegram_web_app,telegram_bridge,telegram_bridge_stub,telegram_bridge_web,telegram_bridge_provider,telegram_auth_service,telegram_theme_adapter}.dart`
- `lib/features/web/{pwa_media_session,ios_guidance_banner,ios_probe_web,ios_probe_stub}.dart`
- `lib/features/settings/data/{update_service,update_platform,update_platform_io,update_platform_stub}.dart`

New data-layer files (3): `tables/news_articles.dart`,
`migrations/0004_news.dart`, `daos/news_dao.dart`.

New web/packaging/infra (14): `web/index.html`, `web/manifest.json`,
`web/service_worker.js`, `web/icons/icon-{48,72,96,144,192,256,384,512}.png`,
`msix_config.yaml`, `flatpak/app.wavely.music.yml`,
`flatpak/app.wavely.music.desktop`, `.github/workflows/release.yml`.

New supabase (1): `functions/telegram-webapp-auth/index.ts`.

New docs (5): `TELEGRAM_MINIAPP.md`, `PACKAGING.md`, `PRIVACY.md`,
`CONTRIBUTING.md`, this report. `KNOWN_LIMITATIONS_FINAL.md` appended.

Modified existing files (11 — additive only): `app_database.dart`
(table/DAO/schemaVersion/hook), `router.dart` (news routes),
`settings_screen.dart` (News row + Check-for-updates row),
`discovery_screen.dart` ("News for you" section, fault-silent),
`main_shell.dart` (iOS banner post-frame hook), `bootstrap.dart`
(Telegram host lifecycle), `playback_engine_web.dart` (media session
wiring), `web_playback_engine.dart` (currentTrack/currentIndex getters +
index tracking in setQueue), `pubspec.yaml` (2 deps), `LICENSE`
(copyright → Dani-Devlop), `CHANGELOG.md`/`README.md` (status).

## 3. Tests authored (all "authored, awaiting local run")

New test files (6 + 3 fixtures):

- `test/features/news/news_service_test.dart` — classifier **15 cases**
  + word-boundary case, Reddit JSON parse (fixture), malformed-JSON
  degradation, Pitchfork/NME RSS parses (fixtures: CDATA strip, guid,
  media thumbnail, enclosure image, RFC-822 date), cache TTL (no network
  within 30 min), offline fallback (dead feed + stored rows), muted
  sources, custom RSS, category filtering.
- `test/features/news/news_screen_test.dart` — loading/loaded/empty/
  error states, article tap → LinkLauncher, chip toggling filters.
- `test/features/news/news_settings_screen_test.dart` — toggle
  persistence, RSS add happy path + non-http rejection + garbage
  rejection, feed removal, muted unmute, `validateRssUrl` unit cases,
  `NewsCategory.tryParse` round-trip.
- `test/features/telegram/telegram_bridge_test.dart` — bridge state
  defaults, io-stub contract, theme mapping (documented keys, garbage
  fallbacks, secondary_bg hint chain), `resolveTelegramTheme` override
  matrix, `kTelegramMode` const.
- `test/features/telegram/telegram_auth_test.dart` — success round
  (raw initData relayed, apikey header, session applied), 400
  invalid_signature, 401 expired, network, non-JSON, missing session,
  empty tokens, empty-initData local rejection (zero requests).
- `test/features/settings/update_service_test.dart` — version compare,
  asset picking, up-to-date/update-available, 403 + network degradation,
  installer seam.
- `test/data/local/db/daos/news_dao_test.dart` — upsert dedupe on the
  unique pair, clearAll, empty no-op, category JSON codec.
- Fixtures: `test/fixtures/news/{reddit_music.json,pitchfork.rss,nme.rss}`.

## 4. Verification status (honest)

- `flutter pub get` / `build_runner` / `flutter analyze` / `flutter test`:
  **NOT run** (no SDK in the sandbox). The codegen surface GREW by the
  new drift table/DAO (`news_dao.g.dart`, `app_database.g.dart`
  regeneration) — first local run must regenerate before analyzing.
- Structural verification run here and passing: import resolution over
  `lib/` + `test/` (script in Step 8), YAML validity
  (`msix_config.yaml`, flatpak manifest, `release.yml`), JSON validity
  (`manifest.json`), secret scan over all new files, and a git-diff audit
  confirming **no Stage 1.1/1.2/2.1 file was rewritten** (additive edits
  only — every modified file's diff is import/appends/small guarded
  hooks).
- Remaining risk is exactly the "authored, awaiting local run" surface:
  codegen output, analyzer lints (very_good_analysis is strict),
  plugin-backed paths (secure storage unchanged; new:
  `cached_network_image`, `auto_updater`), and the Telegram web bindings
  (only exercised inside a real Telegram host).

## 5. Known limitations

1. **Telegram Mini App background audio pauses when leaving the app**
   (host webview suspension; documented in TELEGRAM_MINIAPP.md).
2. **iOS PWA background audio unreliable** (Safari); the guidance banner
   mitigates by pointing at the Mini App.
3. **No remote-track download in the PWA** (io-only executor, unchanged).
4. **Codec support varies by browser**; engine surfaces the error state.
5. **No local file scan on web** (Stage 1.1 stub, unchanged).
6. **PWA icons are generated placeholders** — owner replaces (PACKAGING.md).
7. **MSIX is unsigned** (`sign: false`) — owner provides a certificate.
8. **Telegram find-or-create uses a deterministic derived password** —
   bot-token rotation breaks re-sign-in for existing mappings (surfaced
   honestly as `401 rejected` with a re-provision message).
9. **Per-source cache clearing** (Stage 2.1 limitation) also applies to
   the news feeds' `http_cache` entries.
10. `auto_updater` is wired as a dependency but not yet driving in-place
    installs — the current flow is check + open release page (owner
    decision documented in PACKAGING.md §5).

## 6. Blockers

None for authoring. Owner-provided inputs pending for RELEASE (not for
verification): signing certificate, real icon assets, bot token in
Supabase secrets, deployed web build domain.

## 7. Local verification commands for the owner

```bash
git clone -b feat/stage-2.2 https://github.com/Dani-Devlop/Music_Wavely.git
cd Music_Wavely
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze 2>&1 | tee analyze.log
flutter test 2>&1 | tee test.log

# Web / PWA surface:
flutter build web --dart-define=TELEGRAM_MODE=true

# Telegram edge function (after supabase secrets set TELEGRAM_BOT_TOKEN=…):
supabase functions deploy telegram-webapp-auth --no-verify-jwt
```

## 8. Commit & PR steps (owner runs, not you)

```bash
git fetch origin main
git checkout -B feat/stage-2.2 origin/main
git add -A
git commit -m "feat: stage 2.2 — news, telegram mini app, pwa, desktop packaging"
git push -u origin feat/stage-2.2
# PR against main; do NOT merge before analyze + test pass locally.
```
