# Stage 2.1 Report — Legal Online Sources + Download Manager

Status: **authored, awaiting local run.** No Flutter SDK exists in this
sandbox; `flutter pub get`, `build_runner`, `flutter analyze` and
`flutter test` have never been executed against this tree. Everything below
was verified structurally (import resolution, delimiter balance, symbol
audits) — see `docs/STAGE_2_1_PREFLIGHT.md` and the validation section.

Pre-flight: **PASSED** — `docs/STAGE_2_1_PREFLIGHT.md`.

## 1. What was built

### Section 4 — Subsonic / Navidrome (`lib/sources/subsonic/`)

- `subsonic_source.dart` — `SourceProvider` over Subsonic REST v1.16.1:
  `ping.view` (test connection), `search3.view` (search),
  `stream.view?format=raw` (redirect-resolved stream URL),
  `download.view` (download), `getCoverArt.view` (cover URL),
  `getSong.view` (metadata). Salted-token auth
  (`t = md5(password + salt)`) — the clear-text password never appears in
  a query string (unit-asserted).
- `subsonic_config.dart` — `{url, username, password, apiVersion: 1.16.1}`;
  password persisted via `flutter_secure_storage`
  (`SecureSubsonicCredentialStore`, Keychain/Keystore/EncryptedSharedPrefs),
  non-secret fields in SharedPreferences; in-memory store for tests;
  optional `VaultCredentialSync` seam (additive, no sync-table changes).
- `subsonic_mapper.dart` — tolerant `Child` JSON → `Track` mapping
  (content-type fallback for suffix, created-timestamp parsing, directory
  skipping).
- Live Navidrome contract test (`test/sources/subsonic/navidrome_contract_test.dart`)
  + `docker-compose.navidrome.yml` + CI workflow
  (`.github/workflows/navidrome-contract.yml`, spins Navidrome 0.54.4 on
  4533, seeds a generated sine-wave mp3, runs only the Subsonic tests).
- Settings UI: `lib/features/settings/presentation/widgets/subsonic_config_sheet.dart`
  (URL/username/password + Test connection + Save/Remove).

### Section 5 — Jamendo (`lib/sources/jamendo/`)

- `jamendo_source.dart` — v3.0 API with **user-registered client_id**
  (live-verified: anonymous requests fail with code 5 and the historical
  demo id is suspended with code 11 — recorded in the METADATA_SOURCES
  appendix). Stream = `audio`, download = `audiodownload`, license =
  `license_ccurl`. 2 req/s via the Stage 1.2 `RateLimiter`.
- Contract test with committed fixture (`test/fixtures/jamendo/track_search.json`),
  including the suspended-client_id envelope mapping.

### Section 6 — archive.org (`lib/sources/archive_org/`)

- `archive_org_source.dart` — `advancedsearch.php` (mediatype:audio),
  `/metadata/{id}`, `download/{id}/{file}` URLs; quality preference
  **Flac > VBR MP3 > Ogg Vorbis > other audio**; tolerant parsing of
  list/atom `creator`, `mm:ss`/seconds durations; `identifier|filename`
  pair id.
- Contract tests with committed fixtures
  (`test/fixtures/archive_org/{search,item_metadata}.json`).

### Section 7 — Free Music Archive (`lib/sources/fma/`)

- `fma_source.dart` — **search + license-metadata source**. Live-verified
  findings (recorded honestly): the legacy JSON API is dead (404); the
  search HTML page is parseable (track/artist/duration/downloadOverlay
  anchors); downloads redirect to `/login` (account-gated). Wavely does
  not bypass account walls, so `supportsStreaming/supportsDownload` are
  `false` and both methods throw a documented `SourceApiException`.
  HTML parsing via the `html` package (added to pubspec), robots.txt
  respected (no `User-agent: *` block, specific AI bots only) and
  self-limited to 1 req/2 s.
- License extraction from the downloadOverlay page (CC url) used for
  provenance.

### Section 8 — Unified search

- `lib/features/search/domain/search_service.dart` — parallel fan-out with
  `Future.wait`, per-source 5 s timeout, failed-source collection, merge +
  dedupe by ISRC hook (wired, no Track field carries ISRC today) or by
  normalised title+artist with Levenshtein < 3 (blank artist matches any).
- UI (additive): search screen gains a Library/Online `SegmentedButton`;
  the local FTS path is untouched (default scope = Library, existing
  behavior and keys unchanged). Online pane
  (`online_search_pane.dart`) renders `SourceBadge` (reused Stage 1.1
  component) + quality label per row and a download action that enqueues
  through the DownloadService with a SnackBar confirmation.

### Section 9 — Download manager

- Drift (repo convention `lib/data/local/db/migrations/`, not the spec's
  `lib/data/local/migrations/` — documented deviation):
  - `tables/downloads.dart` — spec'd columns (`trackId` FK nullable,
    `sourceId`, `sourceTrackId`, `targetPath`, `quality`, `status`
    TextEnum queued/downloading/completed/failed/canceled, `progress`,
    `errorMessage`, `startedAt`, `completedAt`, `provenanceJson`) +
    status index.
  - `migrations/0003_downloads.dart` — version 2 → 3, additive
    `createTable`.
  - `daos/downloads_dao.dart` — enqueue/pending/watchByStatuses/progress/
    markStatus/resetInterrupted/clearFinished.
  - `app_database.dart` — additive registration (table + DAO +
    schemaVersion 3 + `from < 3` hook).
- `download_service.dart` — queue with configurable concurrency (default
  3, clamp 1–5), streaming GET with HTTP **Range resume** (and an honest
  fallback: a 200 answer to a ranged request restarts the file instead of
  corrupting it), progress → DB + `Stream<DownloadEvent>`, size
  verification against Content-Length/Content-Range, sha-256 checksum
  over the finished file, provenance sidecar `<trackId>.wavely.json`
  (source, sourceId, url, license, downloadedAt, quality, checksum) also
  mirrored into `provenanceJson`, retry 3× with exponential backoff
  (1 s/2 s/4 s, injectable), pause (cancel + keep partial → queued),
  cancel (delete partial), retry, Wi-Fi-only gate via injected
  connectivity probe.
- `folder_template.dart` — placeholders `{continent} {country} {genre}
  {artist} {album} {year} {title} {trackNumber}`; default
  `Music/{continent}/{country}/{genre}`; every segment sanitized; Unknown
  fallbacks. **Note:** no `ArtistCountryResolver` exists on main (Stage
  1.2 discovery ships the MusicBrainz client but no country resolver), so
  a NEW `ArtistGeoResolver` was written (artist → MusicBrainz origin area
  → static area→continent map, cached per artist, Unknown on any failure).
  No `ArtistCountryResolver` was modified because none existed.
- `filename_sanitizer.dart` — Windows illegal set + control chars +
  trailing dot/space trimming + reserved device names + 200-char clamp
  with extension preservation + unicode preservation + `untitled` fallback.
- `download_notifier.dart` — `DownloadNotifier` interface +
  `flutter_local_notifications` implementation (lazy init, degrades to
  no-op on channel failure) + `NoopDownloadNotifier` for tests; started /
  completed / failed notifications.
- UI: `downloads_screen.dart` (Active / Queued / Completed / Failed
  sections; per-row progress bar, pause, cancel, retry),
  `download_settings_screen.dart` (quality segmented button, folder
  template, storage location, Wi-Fi-only, concurrency slider).
  Library hook: additive app-bar Downloads button (tab count intentionally
  unchanged to avoid breaking Stage 1.1 tests); Settings hook: additive
  Sources + Downloads section groups.

### Section 10 — Settings extensions (all additive)

- Sources group: per-source rows with enable switches, configure actions
  (Subsonic sheet, Jamendo client-id dialog), archive.org/FMA need no
  configuration.
- Downloads group: rows into the downloads screen and download settings
  screen.
- Cache: the existing total-size + clear-all rows remain; **per-source
  clearing is not implementable against the Stage 1.2 HTTP cache** (keys
  are sha256 hashes of METHOD+URL, so no source prefix is recoverable) —
  documented as a known limitation below instead of rewriting Stage 1.2
  clients.

## 2. File inventory

New lib files (35):

- `lib/sources/sources.dart`, `source_registry.dart`,
  `source_providers.dart`, `source_exception.dart`
- `lib/sources/download_file_executor.dart` (+ `_io.dart`, `_stub.dart`,
  `download_file_exports.dart` — conditional-export seam like Stage 1.1's
  `source_file.dart`)
- `lib/sources/subsonic/{subsonic_config,subsonic_mapper,subsonic_source}.dart`
- `lib/sources/jamendo/jamendo_source.dart`
- `lib/sources/archive_org/archive_org_source.dart`
- `lib/sources/fma/fma_source.dart`
- `lib/features/search/domain/search_service.dart`
- `lib/features/search/presentation/online_search_pane.dart`
- `lib/features/downloads/domain/{folder_template,filename_sanitizer}.dart`
- `lib/features/downloads/data/{download_service,download_prefs,download_notifier,download_events,downloads_providers}.dart`
- `lib/features/downloads/presentation/{downloads_screen,download_settings_screen}.dart`
- `lib/data/local/db/tables/downloads.dart`,
  `lib/data/local/db/migrations/0003_downloads.dart`,
  `lib/data/local/db/daos/downloads_dao.dart`
- `lib/features/settings/presentation/widgets/{subsonic_config_sheet,sources_settings_section}.dart`

Modified existing files (7 — additive only, no rewrites):

- `lib/data/local/db/app_database.dart` — table/DAO registration,
  schemaVersion 2→3, `from < 3` migration hook (integration-required).
- `lib/app/router.dart` — appended `/downloads` + `/downloads/settings`
  routes.
- `lib/features/search/presentation/search_screen.dart` — Library/Online
  scope toggle + OnlineSearchPane wiring (default scope unchanged).
- `lib/features/settings/presentation/settings_screen.dart` — appended
  Sources + Downloads `_SectionGroup`s.
- `lib/features/library/presentation/library_screen.dart` — appended
  Downloads app-bar button.
- `pubspec.yaml` — added `html: ^0.15.6` (FMA HTML parsing). No other
  dependency changes.
- `docs/METADATA_SOURCES.md` — appended the Stage 2.1 live-verification
  appendix.

New test files (22, incl. 4 fixture-support files) and fixtures:

- `test/sources/source_contract.dart` (shared suite),
  `subsonic/{subsonic_config,subsonic_mapper,subsonic_source,
  navidrome_contract}_test.dart`, `jamendo/jamendo_source_test.dart`,
  `archive_org/archive_org_source_test.dart`,
  `fma/fma_source_test.dart`, `source_registry_test.dart`
- `test/features/search/{search_service,online_search_pane}_test.dart`
- `test/features/downloads/{downloads_dao,download_service,
  download_settings_screen,downloads_screen,download_prefs,
  download_notifier,folder_template,filename_sanitizer}_test.dart` +
  `integration_download_flow_test.dart`
- `test/features/settings/{subsonic_config_sheet,
  sources_settings_section}_test.dart`
- `test/fixtures/{jamendo,archive_org,fma}/*` (4 fixture files)

Infra: `docker-compose.navidrome.yml`,
`.github/workflows/navidrome-contract.yml`.

Docs: `docs/STAGE_2_1_PREFLIGHT.md`, this file,
`docs/SOURCES_CONTRACT_TESTS.md`, `docs/DOWNLOAD_FOLDER_TEMPLATES.md`,
`docs/METADATA_SOURCES.md` appendix.

## 3. Tests authored (all "authored, awaiting local run")

- Whole test tree: **120 dart files** (was 98 → +22), **1028**
  `test(`/`testWidgets(` invocations (was 857 → +171).
- New suites per this stage:
  - contract suites: shared `runSourceProviderContract` × 4 providers
    (subsonic, jamendo, archive.org, FMA with `expectsStreamFailure`)
    + live Navidrome contract (skip-guarded, CI-driven)
  - unit: folder template **10+3 cases**, filename sanitizer **15+3
    cases**, download retry **5 cases** (backoff order, exhaustion,
    size mismatch, unknown source, retry-after-failure) + Wi-Fi gate +
    Range resume + Range-ignored fallback + pause/cancel/concurrency,
    dedupe **5 cases** + timeouts + parallel fan-out, prefs defaults/
    clamping/sync, notifier degradation, source registry persistence
  - widget: downloads screen (empty / active / failed / completed),
    download settings screen (6), online search pane (5), subsonic
    config sheet (4), sources settings section (5)
  - DAO: 8 cases over an in-memory schemaVersion-3 database
  - integration: mock source → download → template folder + provenance
    sidecar + checksum + progress events
- Golden tests: none — no new design-system components were introduced
  (the stage reuses `SourceBadge`, `ShimmerBox`, `EmptyState`, tokens);
  per the spec golden tests apply only to new components.

## 4. Verification status (honest)

- `flutter pub get` / `build_runner` / `flutter analyze` / `flutter test`:
  **NOT run** (no SDK in the sandbox; owner has no computer this session).
- Structural verification run here and passing:
  - import resolution over `lib/` + `test/`: **OK: all imports resolve**
  - interpolation-aware delimiter balance over 359 dart files: **OK**
  - pre-flight symbol audit: **PASS** (see pre-flight report)
- Static self-review findings fixed during authoring: shared exception
  type extraction (Subsonic/Jamendo), `dart:convert` JSON (replacing an
  over-clever registry hack), double-listen bug in a test's gated stream,
  FutureProvider override async signature, unused/missing imports in 5
  test files, provider type tightening (`List<Object>` →
  `List<SourceProvider>`), service dead-code removal, honest connectivity
  injection instead of a throwing stub.
- Remaining risk is exactly the "authored, awaiting local run" surface:
  riverpod/drift codegen output, analyzer lints (very_good_analysis is
  strict), and runtime behavior of the plugin-backed secure storage /
  notifications paths.

## 5. Known limitations

1. **Jamendo requires a user-registered `client_id`** (demo id suspended).
   Without it the source returns the API's honest error to the UI.
2. **FMA cannot stream or download** — the per-track download endpoint
   redirects to `/login` (account wall, live-verified). Wavely exposes
   FMA as search + license-metadata only.
3. **Per-source cache clearing is impossible** without changing Stage 1.2
   metadata clients: `http_cache` keys are sha256(METHOD URL) with no
   source column. Deferred; an additive plan (new optional `source`
   param on `CachingHttpClient.getJson` + a nullable `source` column via
   migration) is sketched here for the owner's decision.
4. **No `ArtistCountryResolver` existed on main**; `ArtistGeoResolver` is
   new and maps free-form MusicBrainz area names to continents via a
   static table — uncommon areas fall back to `Unknown`.
5. `{year}` uses `Track.addedAt.year` and `{trackNumber}` is a `00`
   constant — the Track entity has no release-year/track-number fields.
6. Download file I/O is io-platform only (conditional-export executor;
   web arm throws like Stage 1.1's `source_file_stub.dart`).
7. `LocalDownloadNotifier` degrades to a no-op if the notifications
   channel fails; channel init only happens on real devices.
8. The Navidrome live contract test is skip-guarded locally and runs in
   CI (`workflow_dispatch` + relevant paths); it has never been executed
   here.
9. `flutter_local_notifications` Android channel id/name are coded as
   `downloads`/`Downloads` with `@mipmap/ic_launcher`; verify the
   launcher icon reference during the local run.

## 6. Blockers

None. Everything in scope is authored; the remaining work is the owner's
local verification pass.

## 7. Local verification steps for the owner

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
docker compose -f docker-compose.navidrome.yml up -d
flutter test test/sources/subsonic/
```

(For the Navidrome run: drop any mp3 into `./docker/navidrome/music/` or
generate one with ffmpeg per docs/SOURCES_CONTRACT_TESTS.md; the login
env vars are in the compose file and the CI workflow.)

## 8. Commit & PR steps (owner runs, not you)

```bash
git fetch origin main
git checkout -B feat/stage-2.1 origin/main
git add -A
git commit -m "feat: stage 2.1 — legal online sources and download manager"
git push -u origin feat/stage-2.1
# then open the PR against main (do NOT squash-merge before analyze+test)
```
