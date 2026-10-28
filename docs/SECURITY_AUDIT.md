# Security Audit — Stage 3

Date: 2025-10-28 · Scope: `main @ 1cd90ca` (Stage 2.2 squash-merged) ·
Method: manual review of security-sensitive code paths + repo-wide pattern
scans (no SDK available; see §Verification).

Severity scale: CRITICAL > HIGH > MEDIUM > LOW > INFO. Every finding has a
`SEC-*` id, a status (`fixed` / `partial` / `documented`), and a fix-risk
note. **Zero CRITICAL and zero HIGH findings.** The two worst issues are the
sync-engine auth gap (BUG-3 in `docs/BUG_FIXES.md`, fixed) and the missing
`user_id` DB defaults (SEC-8, fixed).

---

## Findings

### SEC-1 — Supabase session never persisted (in-memory storage) · MEDIUM · **fixed (final polish)**
- File: `lib/data/remote/supabase_client_provider.dart`
- The client was constructed bare (`SupabaseClient(url, anonKey)`); with
  the bare-constructor architecture, supabase_flutter's `SupabaseAuth`
  persistence layer never runs and sessions died with the process.
- Fix: `attachSessionPersistence` replays a stored session through
  `auth.recoverSession()` at construction and persists on
  `signedIn`/`tokenRefreshed`/`initialSession` (deletes on `signedOut`).
  Storage backend: `flutter_secure_storage` on mobile/desktop,
  SharedPreferences on web. Verified against gotrue 2.27.3 / supabase
  2.16.5 / supabase_flutter 2.18.3 sources (bare gotrue persists only PKCE
  verifiers, hence the explicit adapter). Sign-in now survives restarts,
  which also keeps the sync backend (BUG-3) authenticated across runs.

### SEC-2 — Bot-token compromise enables silent account takeover via derived passwords · MEDIUM · **fixed (final polish)**
- Files: `supabase/functions/telegram-webapp-auth/index.ts`,
  new `supabase/migrations/0003_telegram_user_passwords.sql`
- The Supabase password for every Telegram-mapped user was deterministically
  derived from the bot token alone — a leaked `TELEGRAM_BOT_TOKEN` let an
  attacker compute any user's password and sign in directly.
- Fix: the edge function now provisions a cryptographically random 32-byte
  password (`crypto.getRandomValues`) at find-or-create time and stores the
  mapping ONLY in `telegram_sessions` (new `telegram_user_id`/`password`
  columns; deny-all RLS and no anon/authenticated grants are unchanged).
  Returning users sign in from the stored mapping; a drifted credential is
  re-provisioned server-side. The password is never derivable and never
  returned to clients. Bot-token rotation no longer invalidates accounts.
- Note: after deploying, the migration `0003` must be applied
  (`supabase db push`); old derived passwords become irrelevant because the
  first new sign-in overwrites the account password with a random one.

### SEC-3 — Path traversal via unsanitized `sourceTrackId` in the provenance sidecar path · MEDIUM · **fixed**
- File: `lib/features/downloads/data/download_service.dart:346-347`
- `sourceTrackId` comes from remote source APIs and used to be concatenated
  straight into the sidecar filename; an id like `../../x` wrote outside the
  download dir. The audio filename itself was already sanitized.
- Fix: `sanitizeFilename(row.sourceTrackId, maxLength: 120)` before
  composing the path (same sanitizer as the media file).

### SEC-4 — Replayable Subsonic credentials persisted in the provenance sidecar · MEDIUM · **fixed**
- Files: `lib/features/downloads/data/download_service.dart` (`_provenanceJson`,
  new `_redactedProvenanceUrl`); origin `lib/sources/subsonic/subsonic_source.dart`
- The Subsonic stream URL embeds `t=md5(password+salt)&s=<salt>` — a
  permanently replayable credential on most servers — and was written to
  the sidecar JSON and the DB.
- Fix: `t`/`s`/`p`/`token`/`api_key`/`apikey`/`key` query parameters are
  stripped before persisting; scheme/host/path are kept.

### SEC-5 — Missing HTTP timeouts across hand-rolled clients · MEDIUM · **partial fixed**
- Fixed (with audit-tagged edits):
  - `lib/data/remote/metadata_http.dart` — 15 s per request
    (`kMetadataHttpTimeout`), so a stalled server cannot hang the shared
    rate-limiter queue.
  - `lib/features/ai_chat/data/provider_http.dart` — 30 s per attempt
    (`kProviderHttpTimeout`, injectable for tests); `TimeoutException`
    joins the retry schedule.
  - `lib/features/settings/data/update_service.dart` — 15 s.
  - `lib/sources/subsonic/subsonic_source.dart` — Dio `connectTimeout: 10 s`,
    `receiveTimeout: 30 s`.
- Documented (deliberately not changed):
  - `lib/features/downloads/data/download_service.dart` — the body is a
    long-lived streamed download; a blanket `.timeout()` on the whole
    request would abort large/low-bandwidth transfers. Size verification
    against Content-Length already fails truncated downloads, and
    `resetInterrupted()` repairs rows at boot. A per-chunk idle watchdog is
    the correct future fix.
  - `lib/features/auth/data/telegram_auth_service.dart` — each RPC runs
    under the service's 5-minute flow deadline; per-call timeout adds
    little.
- Fix risk: safe (applied).

### SEC-6 — Parental fallback (ffmpeg failure) was invisible to parents · MEDIUM · **fixed**
- File: `lib/app/providers.dart` (`censorNeeded` branch)
- The documented v1 policy is "censoring must never block playback": when
  the ffmpeg render fails (or lyrics are unsynced so no plan exists), the
  UNCENSORED original plays with no audit trail.
- Fix: both fallback branches now write best-effort local audit events
  (`censor_render_failed`, `censor_skipped_no_synced_lyrics`) through
  `ParentalDao.audit`. The policy itself is now parent-configurable — see
  BUG-9 in `docs/BUG_FIXES.md` (final polish: default `block`, options
  block / mute / allow on the Parental screen).

### SEC-7 — Censor render cache ignored word-list changes · MEDIUM · **fixed**
- File: `lib/features/parental/data/censor_service.dart:77-81`
- Cache key was only the track id, so renders made with an OLD blocked-word
  list kept playing after the list changed.
- Fix: the key now includes a value-stable hash of the mute plan
  (`_planKey`; record-typed ranges hash by value, stable across restarts).

### SEC-8 — Sync payloads omit `user_id`; columns had no `auth.uid()` default · MEDIUM · **fixed**
- Files: new `supabase/migrations/0002_user_id_defaults.sql`;
  context `supabase/migrations/0001_init.sql`, `lib/data/sync/supabase_sync_backend.dart`
- The sync backend pushes rows WITHOUT `user_id`, documenting the contract
  "defaults to `auth.uid()`" — but the columns were `NOT NULL` with no
  default, so every push failed the NOT NULL constraint (and RLS `with
  check` would have rejected null anyway).
- Fix: additive migration sets `default auth.uid()` on `user_id` of
  `devices`, `user_settings`, `plays`, `track_stats_daily`,
  `artist_follows`, `sync_state`, `telegram_links`. RLS policies from
  0001 are unchanged and still scope every table to the caller.

### SEC-9 — Token-minting endpoint CORS: missing methods header · LOW · **fixed (origin documented)**
- File: `supabase/functions/telegram-webapp-auth/index.ts:25-32`
- Preflight for `POST` + `application/json` failed without
  `Access-Control-Allow-Methods` — the Mini App webview path could never
  preflight successfully. Fixed (`POST, OPTIONS`).
- Documented: `Access-Control-Allow-Origin: *` remains. The endpoint is
  HMAC-gated and replay is bounded by the Telegram-spec 1 h window, so this
  is acceptable for v1; when the Mini App is deployed, the owner should
  narrow the origin to the deployed domain.

### SEC-10 — Gemini API key in the URL query string · LOW · **fixed**
- File: `lib/features/ai_chat/data/gemini_provider.dart:47-59`
- `?key=$apiKey` leaks into proxy logs and into exception messages that
  become `Failure.cause`. Fix: key sent via the `x-goog-api-key` header
  (supported by the Generative Language API); URI no longer carries it.

### SEC-11 — Single-iteration SHA-256 for a 4-8 digit PIN · LOW · **fixed**
- File: `lib/features/parental/data/pin_hash.dart`; test updated
  `test/features/parental/pin_hash_test.dart`
- New hashes use `p3$`: sha256 iterated 10,000× (pure-Dart KDF, no new
  dependency). `verifyPin` still accepts `p2$` (salted, single round) and
  legacy v1 plain-sha256, so existing profiles keep unlocking; re-saving a
  PIN upgrades it to v3.

### SEC-12 — Hardcoded dev credential in the committed compose file · LOW · **fixed**
- Files: `docker-compose.navidrome.yml`, `.github/workflows/navidrome-contract.yml`
- `ND_DEVAUTOCREATEADMINPASSWORD: "wavely-ci-password"` → now
  `${NAVIDROME_ADMIN_PASSWORD:?...}` (fails fast when unset) and the CI
  workflow injects the value for the compose step.

### SEC-13 — `telegram-auth` returned raw internal error messages · LOW · **fixed**
- File: `supabase/functions/telegram-auth/index.ts:206-219`
- Fix: callers now get a generic `internal error`; details go to the
  server-side log only.

### SEC-14 — `telegram-webapp-auth` missing from `config.toml` (`verify_jwt` drift) · LOW · **fixed**
- File: `supabase/config.toml:90-95`
- The function authenticates via HMAC itself and the client sends only an
  apikey header; with the platform default `verify_jwt = true`, Supabase
  would 401 before the HMAC runs. The function block is now declared with
  `verify_jwt = false` (matching the two existing functions).

### SEC-15 — Unsigned release artifacts auto-linked by the update checker · LOW · **partial fixed**
- Files: `.github/workflows/release.yml`, `lib/features/settings/data/update_service.dart`
- Fixed: releases now publish `SHA256SUMS.txt` alongside artifacts.
- Documented: `msix` is still added unpinned at release time (existing
  tolerated drift, noted in PACKAGING.md), and the update checker does not
  verify checksums before opening the browser yet — the natural next step
  once real signed artifacts exist.

### SEC-16 — Prompt-injection surface via library metadata sent to the LLM · LOW · **fixed**
- File: `lib/features/ai_chat/data/ai_service.dart` (`_buildSystemPrompt`)
- Track titles/artists (third-party API data) are interpolated into the
  system prompt. Impact was already contained by the executor (track ids
  re-resolved against the DB; fabricated ids rejected — verified clean).
- Fix: the snapshot is now fenced between explicit BEGIN/END delimiters
  with a system-prompt line instructing the model to treat it as data,
  never instructions.

### SEC-17 — Sentry PII scrubbing covered breadcrumbs only · LOW · **fixed**
- File: `lib/app/bootstrap.dart` (`_stripPii`)
- Exception messages and stack frames can embed absolute paths (Dio URIs,
  file-system errors). Verified against the sentry 10.2.0 sources:
  `SentryException.value` and `SentryStackFrame.absPath` are mutable fields
  and `frames` is an unmodifiable view over mutable frame objects.
- Fix: `_stripPii` now also rewrites exception values and frame `absPath`
  through the same path regex (`[path]` placeholder).

### SEC-18 — Compile-time secrets baked into shipped binaries · INFO · **documented**
- File: `lib/core/config/env.dart:17-28`
- `String.fromEnvironment` values (API keys) are extractable from release
  binaries. CI builds without secrets and `.env.example` warns — keep it
  that way: never build releases with personal keys.

### SEC-19 — Freshness check accepted future-dated `auth_date` · INFO · **fixed**
- File: `supabase/functions/telegram-webapp-auth/index.ts:116-124`
- Fix: `auth_date` more than 60 s in the future is now rejected (symmetric
  freshness window).

### SEC-20 — `deleteAccount` RPC has no server implementation; mini-app `TelegramAuthService` unwired · INFO · **documented**
- Files: `lib/features/auth/data/auth_repository.dart:50-60` (graceful
  failure by design), `lib/features/telegram/telegram_auth_service.dart`
- The `delete_account` SQL function does not exist in the migrations yet
  (PRIVACY.md promises account deletion ⇒ data deletion — owner should add
  the function before public launch). The Stage 2.2 mini-app session
  applier has no production call site yet (documented Stage 2.2 limitation).

---

## Clean areas (audited, no findings)

1. **Secrets in code** — repo-wide scan for `ghp_`/`github_pat_`/`sk-`/
   `AIza`/private keys: only dummy test values. No `.env` committed;
   `.gitignore` covers `.env`/`*.env` and keystore files.
2. **Supabase RLS** — every remote table (profiles, devices, user_settings,
   plays, track_stats_daily, artist_follows, sync_state, telegram_links)
   has RLS enabled with owner-only policies; `telegram_sessions` is
   deny-all by design, reachable only via the security-definer
   `redeem_telegram_session` (atomic one-time claim).
3. **Edge function HMAC** — telegram-webapp-auth computes HMAC-SHA256 per
   the Telegram spec, compares timing-safely, checks ≤1 h freshness, never
   logs initData/token, and derives identity only from the verified `user`
   field.
4. **Telegram client auth** — the client never trusts `initDataUnsafe`;
   sessions apply exclusively from the edge-function response; the pending
   sign-in token lives in secure storage with cleanup on stop/complete/
   timeout.
5. **Network TLS** — zero `http://` endpoints; no disabled certificate
   validation anywhere.
6. **Filename sanitization** — `sanitizeFilename` guards separators,
   reserved Windows names, control chars, and length; folder templates all
   pass through it.
7. **Local DB SQLi** — all `customSelect`/`customStatement` use bound
   `Variable`s; the only interpolations are trusted const literals; FTS5
   input is quoted and bound.
8. **Web/PWA** — the service worker never caches audio or authenticated
   responses; only the shell + 5 public metadata hosts are cached.
9. **Crash reporting** — Sentry is opt-in (DSN), `sendDefaultPii = false`,
   `tracesSampleRate = 0`, plus the SEC-17 scrubbing.
10. **Supply chain** — all deps are pub.dev `^` ranges; no `git:`/`path:`
    deps or overrides. Watch items: `ffmpeg_kit_flutter_new` is a community
    fork (acceptable, noted); `msix` unpinned at release time (SEC-15).
11. **ffmpeg executor** — argument-array execution (no shell), paths as
    separate args; censor cache keys sanitized.

## Verification

No Flutter/Dart SDK exists in the audit sandbox: findings come from reading
the actual sources (line numbers verified at merge-commit `1cd90ca`) plus
upstream source verification where APIs were uncertain (sentry 10.2.0,
supabase package storage defaults). All fixes are text edits reviewed by
re-running the repo's own delimiter/import scanners. **`flutter analyze` +
`flutter test` must be run locally before merging** — see
`docs/STAGE_3_REPORT.md` §9 for the exact commands.
