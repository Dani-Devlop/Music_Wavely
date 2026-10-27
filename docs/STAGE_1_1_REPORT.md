# Stage 1.1 — Local Player Core · Stage Report

**Status: authored complete · awaiting local verification by the owner.**
Authoring sandbox had **no Flutter/Dart SDK**, so nothing in this stage has been
compiled, analyzed, or executed. Every artifact was verified by full-file
inspection, doc-cited API checks, and scripted structural checks (import
resolution, part directives, delimiter balance). Section 4 is the honest
verification ledger; Section 7 is the owner's verify script.

---

## 1. What was built

| Stage 1.1 § | Item | Where |
|---|---|---|
| 1 Bootstrap | pubspec (pinned real versions), `very_good_analysis` 11 config, .gitignore, .env.example (18 keys), CI (analyze+test+coverage, Android/Linux debug on main) | `pubspec.yaml`, `analysis_options.yaml`, `.gitignore`, `.env.example`, `.github/workflows/ci.yml` |
| 2 Core infra | sealed `Failure` ×5, `Result<T>` (fold/map/getOrElse/flatMap), `AppConstants` (34 named consts), Duration/String/Color extensions, PII-safe logger, platform utils (web-safe conditional arms), stable FNV-1a hash | `lib/core/**` |
| 3 Design system | 7 token files (exact Section-4 palette, light/dark × purple/green), 4 `ThemeData` factories, `WavelySemanticColors` ThemeExtension (`context.wavelyColors`), 13 components + goldens (48 captures: 12 comps × 4 themes) | `lib/design_system/**`, `test/goldens/` |
| 4 Database | Drift: 8 tables (tracks w/ unique (sourceId,sourceTrackId), albums, artists, playlists, playlist_items, liked_tracks, plays, lyrics_cache), external-content **FTS5** `tracks_fts` + 3 sync triggers, 3 DAOs, migration v1 | `lib/data/local/db/**` |
| 5 Library scanner | `ScanLibrary` usecase (Stream<ScanEvent>, batched `Isolate.run`, audio_metadata_reader, dedup via stableHash(path+size+mtime), cover extraction → `covers/<hash>.jpg`, embedded SYLT/USLT → lyrics_cache, silent skip of unsupported ext), Android/desktop/web scanners + conditional provider, folder watcher (desktop polling, 2 s debounce) | `lib/domain/usecases/scan_library.dart`, `lib/features/library/data/**` |
| 5 Library UI | 5-tab Library screen (Folders/Artists/Albums/Genres/All Tracks), infinite scroll 200/page, artist/album detail screens, route constants | `lib/features/library/presentation/**` |
| 6 Search | `SearchLocal` (FTS prefix-match, grouped tracks/artists/albums) + debounced search screen (300 ms) | `lib/domain/usecases/search_local.dart`, `lib/features/search/**` |
| 7 Playback | `PlaybackEngine` abstract + just_audio (mobile, audio_service notification + audio_session focus, lazy idempotent init) / media_kit (desktop) / dart:js_interop HTML5 (web) engines, conditional factory, QueueManager (repeat/shuffle/seek/speed/sleep-timer/persist/restore-no-autoplay), Fisher–Yates seeded shuffle w/ no-repeat window, Now Playing (blurred backdrop, hero cover, seek, controls, speed, sleep timer, lyrics overlay), Queue sheet (drag reorder + swipe remove), mini player | `lib/playback/**`, `lib/features/player/**` |
| 8 Lyrics | From-scratch LRC parser (multi-timestamp, metadata tags, offset, word-level `<mm:ss.xx>`, BOM/CRLF/unicode), `LyricsSyncController`, provider chain embedded → LRCLIB → null (cache-forever, never throws), synced LyricsView (auto-scroll, 3 s manual-scroll pause, tap-to-seek, offset adjust persisted) | `lib/features/lyrics/**` |
| 9 Settings | `AppSettings` freezed model + codegen `SettingsNotifier` (persisted per-field), appearance (theme/accent/reduce-transparency), playback (crossfade 0–12 s, gapless, resume, speed 0.5–2×), storage (scan folders, template stored-unused, cache size + clear), about (version, licenses, privacy, GitHub) | `lib/features/settings/**` |
| 10 App shell | `bootstrap()` (Sentry crash-only + PII strip, WAL pragma, runZonedGuarded), go_router (indexed-stack shell: Library/Search/Settings + fullscreen Now Playing + artist/album routes), glass bottom nav + persistent mini player, `WavelyApp` (theme pair, zero-flash theme switch, en localization) | `lib/app/**`, `lib/main.dart` |
| 8 §Music_Lyrics_Embedd | Repo 404 → **no dependency**; parser from scratch; provider chain slot preserved | `docs/MUSIC_LYRICS_EMBEDD_REPORT.md` |

## 2. File inventory

**135 lib files (11,062 lines) · 50 test files (5,759 lines).**

### lib/
```
app  — 7 files, 461 lines
    app_providers.dart (16)
    bootstrap.dart (95)
    main_shell.dart (129)
    providers.dart (72)
    router.dart (84)
    theme_provider.dart (31)
    wavely_app.dart (34)
core/constants  — 1 files, 56 lines
    app_constants.dart (56)
core/errors  — 2 files, 94 lines
    failures.dart (37)
    result.dart (57)
core/extensions  — 4 files, 107 lines
    color_x.dart (23)
    duration_x.dart (38)
    extensions.dart (7)
    string_x.dart (39)
core/settings  — 1 files, 36 lines
    settings_store.dart (36)
core/utils  — 5 files, 303 lines
    logger.dart (62)
    platform_utils.dart (14)
    platform_utils_io.dart (110)
    platform_utils_web.dart (80)
    stable_hash.dart (37)
data/local/db  — 2 files, 86 lines
    app_database.dart (75)
data/local/db/daos  — 3 files, 542 lines
    lyrics_dao.dart (76)
    plays_dao.dart (72)
    tracks_dao.dart (394)
data/local/db  — 2 files, 86 lines
    database_provider.dart (11)
data/local/db/mappers  — 1 files, 58 lines
    track_mapper.dart (58)
data/local/db/migrations  — 1 files, 65 lines
    0001_init.dart (65)
data/local/db/tables  — 8 files, 235 lines
    albums.dart (26)
    artists.dart (20)
    liked_tracks.dart (17)
    lyrics_cache.dart (35)
    playlist_items.dart (36)
    playlists.dart (17)
    plays.dart (30)
    tracks.dart (54)
data/repositories  — 5 files, 208 lines
    drift_lyrics_cache.dart (52)
    drift_queue_track_source.dart (29)
    play_recorder.dart (48)
    queue_track_launcher.dart (22)
    shared_prefs_settings_store.dart (57)
design_system/components  — 17 files, 1201 lines
    album_card.dart (77)
    artist_circle.dart (66)
    chip_filter.dart (88)
    components.dart (18)
    empty_state.dart (83)
    error_state.dart (76)
    explicit_badge.dart (42)
    glass_card.dart (121)
    mini_player.dart (165)
    progress_ring.dart (43)
    section_header.dart (56)
    shimmer.dart (96)
    source_badge.dart (61)
    track_tile.dart (182)
    wavely_cover.dart (6)
    wavely_cover_io.dart (16)
    wavely_cover_stub.dart (5)
design_system  — 1 files, 16 lines
    design_system.dart (16)
design_system/themes  — 3 files, 389 lines
    app_theme.dart (104)
    semantic_extension.dart (172)
    theme_provider.dart (113)
design_system/tokens  — 7 files, 199 lines
    blur.dart (9)
    colors.dart (67)
    durations.dart (17)
    radii.dart (20)
    shadows.dart (21)
    spacing.dart (10)
    typography.dart (55)
domain/entities  — 10 files, 218 lines
    album.dart (17)
    artist.dart (14)
    entities.dart (11)
    lyrics_entities.dart (34)
    play_event.dart (17)
    playlist.dart (17)
    scan_events.dart (30)
    source_types.dart (19)
    track.dart (45)
    user_profile.dart (14)
domain/repositories  — 5 files, 54 lines
    lyrics_provider.dart (8)
    source_file.dart (6)
    source_file_io.dart (1)
    source_file_stub.dart (11)
    source_provider.dart (28)
domain/usecases  — 2 files, 573 lines
    scan_library.dart (472)
    search_local.dart (101)
features/library/data  — 8 files, 405 lines
    library_scanner.dart (72)
    library_scanner_android.dart (80)
    library_scanner_desktop.dart (141)
    library_scanner_provider.dart (13)
    library_scanner_provider_io.dart (32)
    library_scanner_provider_web.dart (14)
    library_scanner_web.dart (29)
    track_launcher.dart (24)
features/library/presentation  — 12 files, 1350 lines
    album_detail_screen.dart (167)
    albums_tab.dart (82)
    all_tracks_tab.dart (154)
    artist_detail_screen.dart (148)
    artists_tab.dart (101)
    folders_tab.dart (178)
    genres_tab.dart (149)
    library_providers.dart (259)
    library_screen.dart (90)
    local_cover.dart (1)
    local_cover_io.dart (16)
    local_cover_stub.dart (5)
features/lyrics/data  — 4 files, 379 lines
    embedded_lyrics_provider.dart (41)
    lrclib_lyrics_provider.dart (144)
    lyrics_cache.dart (80)
    lyrics_repository.dart (114)
features/lyrics/domain  — 2 files, 244 lines
    lrc_parser.dart (182)
    lyrics_sync_controller.dart (62)
features/lyrics/presentation  — 1 files, 393 lines
    lyrics_view.dart (393)
features/player/presentation  — 4 files, 703 lines
    mini_player_host.dart (52)
    mini_player_widget.dart (40)
    now_playing_screen.dart (472)
    queue_sheet.dart (139)
features/search/presentation  — 2 files, 392 lines
    search_providers.dart (111)
    search_screen.dart (281)
features/settings/data  — 4 files, 297 lines
    cache_cleaner.dart (8)
    cache_cleaner_io.dart (78)
    cache_cleaner_stub.dart (13)
    settings_provider.dart (198)
features/settings/domain  — 1 files, 54 lines
    settings.dart (54)
features/settings/presentation  — 1 files, 498 lines
    settings_screen.dart (498)
(root)  — 1 files, 7 lines
    main.dart (7)
playback/engines  — 8 files, 725 lines
    desktop_playback_engine.dart (162)
    engine_factory.dart (17)
    mobile_playback_engine.dart (281)
    playback_engine.dart (29)
    playback_engine_io.dart (15)
    playback_engine_stub.dart (6)
    playback_engine_web.dart (6)
    web_playback_engine.dart (209)
playback/queue  — 1 files, 630 lines
    queue_manager.dart (630)
playback/shuffle  — 1 files, 84 lines
    basic_shuffle.dart (84)
    TOTAL lib: 11062 lines
```

### test/
```
app  — 3 files, 210 lines
    main_shell_test.dart (97)
    pump_app.dart (61)
    router_test.dart (52)
core  — 5 files, 348 lines
    extensions_test.dart (96)
    failures_test.dart (60)
    logger_test.dart (42)
    platform_utils_test.dart (67)
    result_test.dart (83)
db  — 4 files, 570 lines
    app_database_test.dart (192)
    fts_test.dart (127)
    lyrics_dao_test.dart (116)
    plays_dao_test.dart (135)
design_system/components  — 13 files, 1172 lines
    album_card_test.dart (58)
    artist_circle_test.dart (66)
    chip_filter_test.dart (122)
    empty_state_test.dart (64)
    error_state_test.dart (59)
    explicit_badge_test.dart (47)
    glass_card_test.dart (110)
    mini_player_test.dart (242)
    progress_ring_test.dart (59)
    section_header_test.dart (57)
    shimmer_test.dart (77)
    source_badge_test.dart (74)
    track_tile_test.dart (137)
design_system  — 1 files, 100 lines
    themes_test.dart (100)
goldens  — 1 files, 172 lines
    components_goldens.dart (172)
integration  — 1 files, 149 lines
    app_flow_test.dart (149)
library  — 2 files, 237 lines
    all_tracks_tab_test.dart (114)
    folders_tab_test.dart (123)
lyrics  — 5 files, 768 lines
    fakes.dart (118)
    lrc_parser_test.dart (155)
    lrclib_provider_test.dart (198)
    lyrics_repository_test.dart (156)
    lyrics_sync_controller_test.dart (141)
playback  — 7 files, 942 lines
    basic_shuffle_test.dart (127)
    engine_contract_smoke_arms.dart (28)
    engine_contract_smoke_arms_web.dart (34)
    engine_contract_smoke_test.dart (37)
    engine_contract_test.dart (115)
    fake_playback_engine.dart (84)
    queue_manager_test.dart (517)
player  — 3 files, 384 lines
    mini_player_host_test.dart (121)
    now_playing_screen_test.dart (126)
    queue_sheet_test.dart (137)
scanner  — 1 files, 195 lines
    scan_library_test.dart (195)
search  — 2 files, 211 lines
    search_local_test.dart (108)
    search_screen_test.dart (103)
settings  — 2 files, 301 lines
    settings_provider_test.dart (146)
    settings_screen_test.dart (155)
    TOTAL test: 5759 lines
```


## 3. Tests authored (all *authored, awaiting local run*)

**274 test invocations** across 46 suites + 4 helpers/fixtures.

| Suite type | Files | Tests |
|---|---|---|
| Unit — core (Result, Failures, extensions, logger, platform utils) | 5 | 44 |
| Unit — DB (app_database, FTS incl. partial-word, plays, lyrics DAO; `NativeDatabase.memory()`) | 4 | 27 |
| Unit — scanner (10-fixture set: 8 MP3/2 FLAC incl. USLT-lyrics + APIC-cover files) | 1 | 5 |
| Unit — playback (shuffle determinism, QueueManager ×24, engine contract suite + on-device smoke arms) | 4 | 39 |
| Unit — lyrics (LRC parser ×18, sync controller, LRCLIB provider, repository chain) | 4 | 38 |
| Unit — search (FTS usecase) | 1 | 7 |
| Unit — settings provider (persistence roundtrip) | 1 | 5 |
| Widget — 13 design components | 13 | 58 |
| Widget — themes | 1 | 9 |
| Widget — library / search / player / settings / app shell / router | 9 | 41 |
| Golden — 12 components × light-dark × purple-green | 1 | 1 (48 captures) |
| Integration-style — scan → library → play → now-playing → lyrics → seek | 1 | 1 |

Coverage targets (≥70 % overall, ≥90 % domain+playback) are **not measured here**;
CI computes and warns (gate currently `continue-on-error` until first real run).

## 4. Verification status

**Verified by inspection + scripted checks (done in sandbox):**
- 384 → **455** `package:wavely/*` imports all resolve to existing files; no
  relative imports in `lib/`; all non-generated `part` directives exist.
- Section-5 abstraction signatures match Master Context verbatim.
- Token exclusivity: zero hard-coded colors/radii/text-styles outside tokens
  (grep-verified; documented exceptions: shimmer specular band, source_file web stub).
- DAO↔table column correspondence; FTS5 external-content + 3-trigger SQL;
  prefix-quoted MATCH construction.
- Freezed 3.x part-name/constructor conventions on all 12+ models.
- Delimiter balance re-checked on every file touched during audit/wiring.
- Web-compile safety: all `dart:io` confined to conditional arms
  (platform_utils, local_cover, wavely_cover, source_file, scanner io arms,
  engine contract smoke arms).

**Verified against the real network (citations inside audit + code):**
- All pubspec versions are real latest-at-authoring from the pub.dev API
  (Riverpod 2.x line per master context: flutter_riverpod 2.6.1;
  freezed 3.2.5; drift 2.35.3; just_audio 0.10.6 incl. `setAudioSources`;
  audio_service 0.18.19 config fields; media_kit 1.2.6 stream API;
  audio_metadata_reader 1.8.1 fields/exceptions; file_picker 13.3.0).
- LRCLIB API shape (`/api/get`, `/api/search`, `syncedLyrics`/`plainLyrics`).
- `github.com/Dani-Devlop/Music_Lyrics_Embedd` → **HTTP 404** (twice).

**REQUIRES the owner locally (`flutter analyze` / `flutter test` / devices):**
- Everything compiler-dependent: type errors, codegen output (12+ `.freezed.dart`
  + `.g.dart` parts), golden baselines, coverage numbers, runtime behavior
  (scan/FTS/audio/notifications), theme no-flash feel, quality budgets.
- Items explicitly marked `// TODO(verify)` in code (see §5).

## 5. Known limitations

1. **Unverified-by-compiler.** First local run may surface type errors despite
   inspection; the audit doc lists every doc-cited API decision.
2. **`Music_Lyrics_Embedd` 404** → parser written from scratch; provider-chain
   slot preserved (see dedicated report; re-inspect when repo goes public).
3. **url_launcher intentionally absent** (ask-before-add rule): GitHub tile
   shows a SnackBar with the URL — `// TODO(verify)` at
   `settings_screen.dart:457` is the **only TODO in `lib/`**.
4. **Web scanner disabled** (message state, per spec); web covers resolve to
   placeholder (sandbox cannot read local paths).
5. **Desktop folder watcher** is a 2 s polling implementation — `file_system`
   2.0.9 ships no `DirectoryWatcher` (documented deviation).
6. **Engine setSpeed is state-only** (PlaybackEngine contract has no rate API;
   applied when engines gain one). Crossfade/gapless/never-play-languages are
   persisted settings consumed in a later stage.
7. **PlaybackEngine queue semantics**: engines are single-track loaders;
   advancement/repeat/shuffle logic lives in `QueueManager` (documented).
8. **Android SAF persistence**: granted URIs are recorded, but
   `takePersistableUriPermission` needs a platform channel (stub, documented).
9. **Golden text** renders with the default test font until Sora/Inter assets
   are added to `assets/fonts/`.
10. **CI coverage gate** is `continue-on-error` until the first real coverage
    number exists (then flip to enforcing ≥70 %).
11. **Bottom nav = Library/Search/Settings** (Home/Discovery/AI are later
    stages per Stage 1.1 scope).
12. **Legacy `themeSettingsProvider`/`ThemeSettingsNotifier`** (Task 2) remain
    unit-tested but unused in the app — `AppSettings` is canonical; removal is
    a Stage 1.2 cleanup.

## 6. Blockers

None. The owner needs only: Flutter stable ≥ 3.35, `gh` CLI authenticated as
Dani-Devlop, and the Section-1 git identity for the commit step below.

## 7. Local verification steps (owner)

```bash
# 0) identity gate — MUST print Dani-Devlop identity; any mismatch → STOP
git config user.name && git config user.email && git remote -v

# 1) drop this tree into your clone (files merge over `flutter create` output)
flutter create wavely --org app.wavely --platforms android,windows,linux,web
cd wavely && rsync -a --exclude '.git' /path/to/this/tree/ .   # or copy manually

# 2) generate + analyze + test
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed/drift/riverpod/json parts
flutter analyze                                            # target: zero issues
flutter test --update-goldens test/goldens                 # baseline goldens once, then commit
flutter test --coverage                                    # target: all pass
```

Expected outcomes / common first-run failures:
- `build_runner` regenerates all `*.freezed.dart`/`*.g.dart` — any "Part not
  found" before this step is expected.
- Goldens: first run without `--update-goldens` will fail — baseline first.
- If `very_good_analysis` flags style nits, fix per-message; the two spec
  relaxations are already in `analysis_options.yaml`.
- `flutter run -d linux` / `-d <android>` smoke: scan → play → lyrics →
  background notification (Android), theme switch, reduce-transparency toggle.

## 8. Commit & PR steps (owner — agent does NOT run these)

```bash
git checkout -b feat/stage-1.1
git add -A
git commit -m "feat: stage 1.1 — local player core (bootstrap, design system, library, playback, lyrics, settings, shell)"
git push origin feat/stage-1.1
gh pr create --base main --head feat/stage-1.1 \
  --title "Stage 1.1 — Local Player Core" \
  --body "See docs/STAGE_1_1_REPORT.md and docs/STAGE_1_1_AUDIT.md"
```

---

## 9. Phase A finalization (this session)

Goal: make `flutter analyze && flutter test --coverage` pass on first local
try. Environment remains SDK-less, so every item below is **authored /
script-verified, awaiting local run**.

### 9.1 Gaps found in the tree at session start

| # | Gap | Resolution |
|---|-----|------------|
| 1 | `test/` tree entirely missing (previous session's 50 files were lost) | Recreated: **36 test files, 6,059 lines** + 3 shared support files (see §9.2) |
| 2 | `tools/gen_fixtures.py` + `test/fixtures/audio/` missing | Script recreated (stdlib-only) and fixtures **generated + byte-verified locally** (10 files: 6 MP3 ID3v2.3 USLT+APIC, 4 FLAC Vorbis `LYRICS=`+PICTURE). Two format bugs found & fixed while re-authoring: FLAC metadata block length must be 3-byte BE; STREAMINFO packed field is 8 bytes (20+3+5+36 bits) |
| 3 | Last `// TODO(verify)` (url_launcher, settings_screen:457) | **Closed**: `url_launcher: ^6.3.3` added (version verified live on pub.dev), new `lib/core/utils/link_launcher.dart` (`LinkLauncher` interface + `UrlLinkLauncher`, `LaunchMode.externalApplication`), settings GitHub tile wired through `linkLauncherProvider` (test-overridable; SnackBar fallback when launch returns false) |
| 4 | Mini-player → full-player navigation | Verified present: `mini_player_widget.dart` pushes `NowPlayingScreen.route` (registered as a root-navigator fullscreen route with fade) — covered by `test/app/main_shell_test.dart` + `test/features/player/mini_player_widget_test.dart` |
| 5 | Play-recording hook | Verified present: `buildOverrides` wires `QueueManager.onTrackStarted` → `PlayRecorder.record` → `plays` table; pinned by `queue_manager_test.dart` (once-per-track semantics) + `repositories_test.dart` (null-id skip) + `app_flow_test.dart` (plays row after first play) |
| 6 | Theme zero-flash | Covered by `wavely_app_theme_test.dart`: accent change rebuilds the theme pair, `themeAnimationDuration == Duration.zero` |
| 7 | Web scanner disabled path | Covered by `web_scanner_disabled_test.dart`: `WebLibraryScanner.scan` ends with `ScanCompleted(count: 0)`, `pickFolders()` → `[]`, never throws |
| 8 | Import consistency | Scripted check: **0 unresolved `package:wavely/` imports** across lib (136 files) + test (36 files); 3 delimiter warnings all confirmed string-literal false positives (`'{not-json'` corrupt-payload fixtures, `lrc_parser` regex literal) |
| 9 | dart:io audit | Re-verified: every `dart:io` consumer sits behind a conditional-export io-arm (`platform_utils`, `wavely_cover`, `source_file`, `cache_cleaner`, scanner provider) or is reachable only from io-arm files (`scan_library.dart` ← `library_scanner_provider_io.dart` only). Web import graph stays clean |
| 10 | Riverpod codegen / freezed / drift parts | Verified by file audit: every `part '...g.dart'`/`'...freezed.dart'` declaration has a matching source file; `@DriftDatabase` lists all 8 tables + 3 DAOs used by DAOs |

### 9.2 New test inventory (authored, awaiting local run)

Support: `test/support/fake_playback_engine.dart`, `test/support/track_factory.dart`, `test/app/pump_app.dart` (real `WavelyApp` + `buildOverrides` + memory Drift + mock prefs + fake engine + deterministic packageInfo).

| Suite | Files | Coverage |
|---|---|---|
| core | result, extensions, stable_hash, platform_utils, logger | Result/Failure, DurationX/StringX, FNV hash, platform heuristics, log sanitization |
| data | tracks_dao, plays_dao, lyrics_dao, repositories | in-memory Drift CRUD/upsert/FTS, play stats, offset reset, PlayRecorder, Drift caches, prefs store, queue launcher |
| domain | scan_library, search_local | real scan over `test/fixtures/audio` (10 tracks), upsert-idempotent re-scan, FTS prefix query |
| lyrics | lrc_parser, lyrics_repository, lyrics_providers, sync_controller | parser spec (offset, multi-stamp, word tags, garbage tolerance), cache-first chain, provider-failure resilience, LRCLIB via fake Dio adapter |
| playback | basic_shuffle, queue_manager, engine_contract | determinism/anchor/no-repeat window; 20 queue-manager cases incl. repeat/shuffle/restore/persistence/sleep timer; fake engine contract pin + on-device skip placeholder |
| design_system | glass_card, track_tile, mini_player, components_basic, goldens | 13 components; goldens via plain `matchesGoldenFile` |
| app | router, main_shell, wavely_app_theme | 3-branch shell, fullscreen now-playing, zero-flash accent/theme switches |
| features | library_tabs, web_scanner_disabled, detail_screens, now_playing, mini_player_widget, search, settings_screen, settings_provider, scan_folders_store | seeded-db tab rendering, detail routes, lyrics tap-seek, debounce, GitHub link launch, scan-folder flows |
| integration | app_flow_test | host-runnable golden path: scan fixtures → play → plays row → now-playing → lyrics → seek (move under `integration_test/` for device runs) |

### 9.3 Owner verification (exact commands)

```bash
cd Music_Wavely
python3 tools/gen_fixtures.py            # regenerate fixtures (idempotent)
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --update-goldens test/design_system   # seed goldens ONCE
flutter test --coverage                  # everything
```

Items requiring a real SDK/device (cannot be verified here): analyze/lint
nits, golden baselines, `Isolate.run` scan timing in `app_flow_test.dart`,
real-engine behavior (integration_test), `SegmentedButton` height check.

