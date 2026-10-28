# Bug Hunt — Stage 3

Date: 2025-10-28 · Scope: `main @ 1cd90ca` · Method: manual review of the
10 highest-risk feature areas (playback, scan, sync, downloads, lyrics,
parental, AI tools, auth, onboarding, search) with exact file:line evidence.

Every finding has a `BUG-*` id, status (`fixed` / `documented`) and
fix-risk. **Two of these were compile errors** — the sync engine and the
queue manager did not build as merged (BUG-1, BUG-2).

---

## HIGH

### BUG-1 — Sync pull dedupe cache iterated a `Future` (compile error) · **fixed** (safe)
- File: `lib/data/sync/sync_service.dart` (`_applyRemotePlays`)
- `for (final play in _playsDao.playsForTrack(trackId))` — `playsForTrack`
  returns `Future<List<PlayRow>>`; a `Future` is not `Iterable`, so the
  pull half of sync did not compile.
- Fix: the dedupe cache is prefetched for the batch's matched track ids
  before the loop (the enclosing function is already async); `startsFor`
  stays synchronous.

### BUG-2 — `decision` referenced outside its declaring block (compile error) · **fixed** (safe)
- File: `lib/playback/queue/queue_manager.dart` (`_loadCurrent`)
- `TrackLoadDecision? decision;` was declared inside `if (hook != null) {}`
  but read after the block — undefined identifier, queue_manager.dart
  failed analysis and the app build with it.
- Fix: declaration hoisted above the `if` (semantics unchanged; the
  existing queue_manager tests pin the replacement-vs-setQueue behaviour).

### BUG-3 — Sync backend ran unauthenticated: every push 403'd, every pull empty · **fixed** (safe)
- File: `lib/data/sync/sync_providers.dart` (`syncBackendProvider`)
- The backend built its own bare anon-key `SupabaseClient` with no session
  ever attached. Remote tables are RLS-locked to `user_id = auth.uid()`, so
  sync silently never worked — outbox rows parked after 5 attempts, pulls
  returned empty pages — even for signed-in users.
- Fix: the backend now reuses the app's auth-bound client
  (`supabaseClientProvider`); a signed-in session automatically sends the
  `Authorization` header. Signed-out behaviour is unchanged (403s park rows
  and surface in the UI).
- Residual: none — the client's auth storage is now persistent (SEC-1
  final polish), so a signed-in session survives restart.

## MEDIUM

### BUG-4 — Download pause/cancel race orphaned running jobs → concurrent writers on one file · **fixed** (safe)
- Files: `lib/features/downloads/data/download_service.dart`
  (`_runJob` finally, `pause`, `cancel`)
- `pause()` removed the job from `_active` and pumped immediately — before
  the cancelled `_runJob` unwound. The pump could start a second job for
  the same row; the old job's `finally` then removed the NEW job's entry,
  leaving it unpausable, and both jobs appended to the same file.
- Fix: the `finally` removes only when the registered cancel token is
  still this job's (`identical` check); `pause`/`cancel` no longer remove
  the entry themselves.

### BUG-5 — Duplicate enqueues wrote two jobs to the same target path · **fixed** (safe)
- Files: `lib/features/downloads/data/download_service.dart` (`enqueue`),
  `lib/data/local/db/daos/downloads_dao.dart` (new `activeForSourceTrack`)
- The target path derives purely from metadata; two enqueues of the same
  track ran concurrently and appended to one file (corruption + duplicate
  rows).
- Fix: `enqueue` first looks up an existing queued/downloading row for the
  same `sourceId`+`sourceTrackId` and reuses it (plain drift query, no
  codegen impact).

### BUG-6 — Pull watermark used the client wall clock; offline plays were skipped forever · **fixed** (safe)
- File: `lib/data/sync/sync_service.dart` (pull tail)
- The watermark was written as `DateTime.now()` while the backend filters
  `gt('started_at', since)` on the RECORDING device's clock — plays
  recorded earlier but uploaded later (offline, or a behind clock) were
  permanently below the watermark.
- Fix: the watermark now anchors to the newest pulled play's `started_at`
  and only advances when the batch is non-empty; the dedupe cache makes
  conservative re-pulls safe.

### BUG-7 — Library scan "cancel" did not cancel · **fixed** (safe)
- Files: `lib/domain/usecases/scan_library.dart` (batch loop)
- `ScanStateNotifier.cancel()` only cancelled the UI's subscription; the
  scan loop had no cancellation check and kept parsing + writing to
  completion (a re-scan then ran concurrently with the "cancelled" one).
- Fix: between batches the loop bails out when the controller has no
  listener — checked only after the first batch so a not-yet-listened
  stream is not misread as cancelled.

### BUG-8 — Re-scan duplicates re-tagged files and never prunes deleted ones · **documented (needs SDK)** 
- File: `lib/domain/usecases/scan_library.dart` (identity = `stableHash('$path:$size:$mtimeMs')`)
- Editing tags changes size/mtime → new `sourceTrackId` → duplicate row
  with the stale row kept; files deleted on disk are never reconciled
  (orphan rows then error at playback).
- Recommended fix: key the upsert by path (keep id/playCount), and prune
  `local` tracks whose path was not seen in a full (non-partial) scan.
- Fix risk: needs-SDK — pruning semantics need care with per-folder scans
  and an integration test; not safe to change blind.

### BUG-9 — Explicit track with unsynced lyrics played uncensored with no trace · **fixed (final polish: policy enforced)**
- Files: `lib/app/providers.dart`, new
  `lib/features/parental/data/no_lyrics_policy.dart`,
  `lib/features/parental/data/parental_providers.dart`,
  `lib/playback/queue/queue_manager.dart`, `lib/playback/engines/*`,
  `lib/features/parental/presentation/parental_screen.dart`
- `TrackFilter.evaluate` judges the track explicit from plain-text lyrics,
  but `CensorPlanner.plan` returns no plan for unsynced lyrics and the
  adapter fell back to the original file silently (legacy "censoring must
  never block playback" rule).
- Final fix: a parent-configured `NoLyricsPolicy` (`block` / `mute` /
  `allow`) now governs BOTH impossible-censoring paths (no synced lyrics
  and failed ffmpeg render). DEFAULT is `block`: the track is skipped and a
  UI toast explains why (new root `scaffoldMessengerKey` surfaces toasts
  from the non-UI preload hook). `mute` plays the original at engine
  volume 0 (`PlaybackEngine.setVolume`, implemented on all three engines);
  only the explicit `allow` choice plays uncensored — both bypass paths
  stay audited. Unknown/absent stored values parse to `block` (fail-safe).

### BUG-10 — Restored queue showed the persisted position but restarted at 0:00 · **fixed** (safe)
- File: `lib/playback/queue/queue_manager.dart` (`restore`)
- `restore()` displayed `positionMs` but `_loadCurrent()` loaded the
  engine at zero, so resume was cosmetic.
- Fix: after the initial load, restore seeks to the persisted offset
  (guarded; a failed seek cannot break restore).

### BUG-11 — Shuffle state not persisted: restart adopted the shuffled order as "original" · **fixed** (safe)
- File: `lib/playback/queue/queue_manager.dart` (`_persist` / `restore`),
  `lib/core/constants/app_constants.dart`
- Persisted data was ids/index/position only. After a restart with shuffle
  on, the shuffled order became `_unshuffledTracks`, so un-shuffling could
  never restore the album order and `previous()` history was wrong.
- Fix: shuffle/repeat modes are persisted, plus the pre-shuffle id list
  while shuffled; `restore()` rebuilds the true original order (and maps
  the current index back into it).

## LOW

### BUG-12 — Telegram sign-in poll timer leaked after completion · **fixed** (safe)
- File: `lib/features/auth/data/telegram_auth_service.dart` (`_complete`)
- `_complete` nulled `_pending` without cancelling the 2 s `Timer.periodic`
  — it kept firing no-ops for the session and allowed overlapping
  `start()` calls. Fix: capture and cancel the pending timer with the flow.

### BUG-13 — Onboarding Finish double-tap created duplicate 'family' profiles · **fixed** (safe)
- File: `lib/features/onboarding/presentation/onboarding_flow.dart` (`_finish`)
- No re-entrancy guard; two concurrent flushes inserted two parental
  profiles. Fix: `_finishing` guard (resets on failure so the user can
  retry). Kill-mid-wizard was already safe (completion is persisted last).

### BUG-14 — Search dedupe collapsed distinct short titles · **fixed** (safe)
- File: `lib/features/search/domain/search_service.dart` (`_sameWork`)
- Levenshtein distance < 3 with no length guard merged "Run"/"Sun";
  the ISRC hook is dead code (`isrcOf` always null) so ids never keyed
  dedupe. Fix: titles shorter than 5 chars require exact equality
  (documented in-code). ISRC plumbing remains future work.

### BUG-15 — Outbox drain order violated for same-second enqueues · **fixed** (safe)
- File: `lib/data/local/db/daos/sync_outbox_dao.dart` (`pending`)
- `createdAt` has second precision in drift; rows enqueued within the same
  second had no guaranteed FIFO order for LWW-sensitive tables.
- Fix: deterministic `id` tiebreaker appended to the ordering term.

---

## Clean areas (checked, no bugs found)

- **AI tool execution** — fabricated track ids rejected whole-call via
  `TracksDao.byIds` re-resolution; empty results reported cleanly; executor
  errors fed back to the model; tool loop bounded (`maxTurns = 4`).
- **Lyrics sync** — parser emits sorted lines; linear rescan handles
  backward seeks; offset changes rebuild the controller; lifecycle is
  dispose-safe.
- **Metadata clients** — HTTP-200 error envelopes, per-source rate limiter
  (no deadlock), stale-while-error caching, MusicBrainz UA etiquette.
- **Word matcher / censor planner** — boundaries, leet normalization,
  whitelist suppression, and range merge are correct.
- **Playback engines** — dispose ordering, completed-state guards, index
  clamping all correct; repeat-one + shuffle interplay already handled
  repeat-one before any queue advance.
- **Queue index math** — reorder/remove adjustments and the all-blocked
  skip chain are correct and bounded.
- **Auth flows** — polling has deadline + cancel + in-flight guard;
  validation and error surfacing fine.
- **Downloads (other)** — size verification, 200-after-Range restart,
  boot-time `resetInterrupted`, retry/backoff with cancel rethrow all
  correct.
- **Sync push integrity** — outbox rows are deleted only after a confirmed
  successful push; parked rows surface in the UI.

## Verification

No SDK in the sandbox: every fix is a reviewed text edit re-validated by
the repo's delimiter/import scanners; the two compile errors were confirmed
by reading the exact scopes. `flutter analyze && flutter test` locally is
the gate before merging — commands in `docs/STAGE_3_REPORT.md` §9.
