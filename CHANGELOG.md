# Changelog

All notable changes to Wavely. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).


## [0.1.2-dev] - Unreleased

### Compile debt resolution (Iteration 2 — Cloud CI driven)

- Analyzer errors reduced from 425 to **0** (`flutter analyze` clean of
  errors; remaining 2 055 entries are lint infos from very_good_analysis).
- Test suites unblocked: previously 104 suites failed to load (compile
  errors); CI now reports **1 082 passing / 91 failing / 6 skipped**.
- Highlights:
  - Restored conditional-export `File` seam (`SourceProvider.download`
    returns the platform file; `fileAt` declared `dynamic` because the
    analyzer cannot unify the io arm with the web stub).
  - FTS5: removed the invalid table alias in `searchFts` MATCH queries and
    fixed `ftsPrefixQuery` quote escaping per the documented contract.
  - DAOs: `customStatement` calls replaced with typed builder upserts
    (`lyrics_dao.upsert`, `plays_dao.incrementTrackPlayStats`) — raw
    sqlite3 binding rejected drift `Variable` objects.
  - LRC parser: a trailing newline no longer emits an empty gap line.
  - Theme: `context.wavelyColors` falls back to the default token set
    instead of crashing when the Wavely theme extension is absent.
  - Test infrastructure: missing imports (material, metadata_http,
    http/testing, entities, drift `Value`), Riverpod 3 `valueOrNull` ->
    `value`, go_router 18 `initialLocation`, package_info_plus 10
    `buildSignature`, cached_network_image 4 `errorWidget`, drift 2.35
    `NativeDatabase.createInBackground`, dart:js_interop_unsafe imports.
### Stage 3 — Comprehensive audit (authored, awaiting local run)
### Stage 3 — Comprehensive audit (authored, awaiting local run)

#### Security fixes
- Download provenance: `sourceTrackId` sanitized in the sidecar path
  (path traversal) and credential-bearing query params (`t`/`s`/`p`/keys)
  stripped from the persisted URL (SEC-3, SEC-4)
- HTTP timeouts everywhere they were missing: metadata (15 s), AI provider
  per-attempt (30 s), update check (15 s), Subsonic Dio connect/receive
  (SEC-5)
- Parental: censor fallbacks now audited; render cache invalidated when
  the word list changes (SEC-6, SEC-7)
- New migration `0002_user_id_defaults.sql`: `user_id default auth.uid()`
  on all sync tables — makes the documented sync contract real (SEC-8)
- Edge functions: CORS methods header + future-dated `auth_date` rejection
  (telegram-webapp-auth), generic internal errors (telegram-auth),
  `verify_jwt = false` declared in config.toml (SEC-9, SEC-13, SEC-14,
  SEC-19)
- Gemini API key moved from URL query to `x-goog-api-key` header (SEC-10)
- PIN hashing hardened to iterated sha256 (`p3$`, 10k rounds; p2/v1 still
  verify) (SEC-11)
- Navidrome compose password no longer hardcoded; CI injects it (SEC-12)
- AI prompt-injection: library snapshot fenced as data with explicit
  delimiters (SEC-16)
- Sentry scrubbing extended to exception messages and stack-frame paths
  (SEC-17); release artifacts now ship SHA256SUMS.txt (SEC-15)
- Full audit: `docs/SECURITY_AUDIT.md` (0 CRITICAL, 0 HIGH)

#### Bug fixes
- Compile blockers: missing `await` in sync pull dedupe (BUG-1);
  out-of-scope `decision` in the queue preload hook (BUG-2)
- Sync engine now authenticates via the app's session client — pushes no
  longer 403 for signed-in users (BUG-3); pull watermark anchored to
  pulled plays instead of the local clock (BUG-6); deterministic outbox
  FIFO ordering (BUG-15)
- Downloads: pause/cancel race eliminated (identity-checked job cleanup),
  duplicate enqueues deduped (BUG-4, BUG-5)
- Queue: restore seeks to the persisted position; shuffle/repeat + the
  pre-shuffle order persist across restarts (BUG-10, BUG-11)
- Scan cancellation is honoured between batches (BUG-7)
- Telegram sign-in poll timer no longer leaks; onboarding Finish is
  re-entrancy safe; search dedupe no longer collapses short titles
  (BUG-12, BUG-13, BUG-14)
- Full detail: `docs/BUG_FIXES.md`

#### Tests added
- 3 new suites / 27 cases (authored, awaiting local run): news category
  classifier (15), AI provider retry/timeout contract (7), download event
  contract (5); PIN-hash suite rewritten for the v3 format
- Totals: 120 test files / 1114 cases; matrix + integration specs in
  `docs/COVERAGE_AUDIT.md`

#### Docs added
- `docs/SECURITY_AUDIT.md`, `docs/BUG_FIXES.md`, `docs/COVERAGE_AUDIT.md`,
  `docs/STAGE_3_REPORT.md`

## [0.1.0-dev] - Unreleased

### Stage 1.1 — Local Player Core
- Local library scan, playback, synced lyrics, search, settings, app shell

### Stage 1.2 — Auth, Sync, AI, Parental, Analytics, Discovery
- Supabase auth (email + Telegram), sync engine, AI chat, parental control,
  advanced shuffle, analytics, onboarding wizard, discovery metadata

### Stage 2.1 — Legal Online Sources + Download Manager
- Subsonic/Navidrome, Jamendo, archive.org, FMA providers
- Unified search, download manager with folder templates + provenance

### Stage 2.2 — News, Telegram Mini App, PWA, Desktop Packaging
- News: Reddit JSON + Pitchfork/NME/custom RSS, keyword classifier,
  offline cache via the existing http_cache (30-min TTL)
- Telegram Mini App: dart:js_interop bridge, HMAC-validated initData edge
  function, theme adapter, compile-time TELEGRAM_MODE
- PWA: manifest + placeholder icons, service worker (shell precache +
  SWR metadata cache, audio never cached), Media Session wiring,
  iOS guidance banner
- Desktop: MSIX config (unsigned), Flatpak manifest + .desktop,
  GitHub-Releases auto-update check, tag-driven release workflow
- Docs: TELEGRAM_MINIAPP, PACKAGING, PRIVACY, CONTRIBUTING; LICENSE
  copyright → Dani-Devlop
- Authored on `feat/stage-2.2` (was absent before Stage 2.2 authoring —
  see `docs/STAGE_2_2_REPORT.md`); awaiting owner local verification

### Pending
- Local verification: `flutter pub get` + `build_runner` + `flutter analyze`
  + `flutter test` have **never been run** (no Flutter SDK in the authoring
  sandbox) — see `docs/FINAL_VERIFICATION.md` for the copy-paste flow
- First-run fixes from that verification
- Stage 2.2 implementation
