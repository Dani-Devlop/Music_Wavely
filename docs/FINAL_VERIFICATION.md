# Final Verification Guide — Wavely on `main`

Consolidated single-source guide for the owner's first local verification
pass. Generated at Stage 2.2 close-out (PR #2 squash-merged as `c183df2`).
Everything below reflects the **actual** tree on `main` — including honest
gaps (Stage 2.2 is not present; nothing has ever been compiled).

---

## 1. Current state on `main`

**History**

| Commit | Message |
|---|---|
| `c183df2` | Stage 2.1 — Legal Online Sources + Download Manager (#2) ← HEAD |
| `e9b2460` | Stage 1.1 + 1.2 source tree |
| `f2d343d` | Initial commit |

- HEAD author: the **Dani-Devlop** GitHub account (squash merge of PR #2,
  performed via the API with the owner's fine-grained PAT).
- Branches: **`main` only** (`feat/stage-2.1` deleted after merge).

**File counts (408 tracked files)**

| Area | Files |
|---|---|
| `lib/` | 243 (359 `.dart` in the whole tree incl. tests) |
| `test/` | 135 blobs — **120 Dart test files**, 15 fixtures (audio/json/html) |
| `docs/` | 14 |
| `supabase/` | 4 (config + migration + 2 edge functions) |
| `.github/workflows/` | 2 (`ci.yml`, `navidrome-contract.yml`) |
| root / infra | `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`, `README.md`, `.env.example`, `docker-compose.navidrome.yml`, `tools/`, `third_party/`, `assets/` |

**Tests**: **1028** `test(`/`testWidgets(` invocations across the 120 Dart
test files. Golden tests: **none exist** (see §5c).

**Stage completion status**

| Stage | Scope | Authored | Verified locally |
|---|---|---|---|
| 1.1 | Local player core | ✅ | ❌ never run |
| 1.2 | Auth, sync, AI, parental, analytics, discovery | ✅ | ❌ never run |
| 2.1 | Legal online sources + download manager | ✅ (PR #2 → `c183df2`) | ❌ never run |
| 2.2 | News, Telegram Mini App, PWA, desktop packaging | ⛔ **not present** | — |
| — | Local verification pass | ⏳ pending | — |

> ⛔ **Stage 2.2 discrepancy (the only content blocker):** the close-out brief
> expected PR #3 (`feat/stage-2.2`) to be open. GitHub shows **no PR #3, no
> `feat/stage-2.2` branch, and no Stage 2.2 artifacts anywhere** (no
> `lib/features/news`, no Telegram Mini App, no `web/`/`manifest.json`, no
> MSIX/AppImage/Flatpak packaging, no auto-updater; PR #2's 70 changed files
> contain none of these paths). Stage 2.2 was never authored or pushed. It
> must be built in a future session — it is **not** hiding in this tree.

---

## 2. Local verification — copy-paste block

Run on any machine with the Flutter SDK (stable channel):

```bash
git clone https://github.com/Dani-Devlop/Music_Wavely.git
cd Music_Wavely
flutter pub get 2>&1 | tee pubget.log
dart run build_runner build --delete-conflicting-outputs 2>&1 | tee codegen.log
flutter analyze 2>&1 | tee analyze.log
flutter test --update-goldens test/design_system 2>&1 | tee goldens.log
flutter test --coverage 2>&1 | tee test.log

echo "=== SUMMARY ==="
echo "analyze errors: $(grep -c 'error:' analyze.log 2>/dev/null || echo 0)"
echo "test failures: $(grep -c 'failed' test.log 2>/dev/null || echo 0)"
grep 'error:' analyze.log 2>/dev/null | head -20
tail -30 test.log 2>/dev/null
```

Optional extras:

```bash
# Navidrome live contract test (skip-guarded without docker):
cp /path/to/any.mp3 docker/navidrome/music/song.mp3   # or generate with ffmpeg
docker compose -f docker-compose.navidrome.yml up -d
flutter test test/sources/subsonic/
```

Notes:

- **Run `build_runner` BEFORE `analyze`** (the block above does). Skipping it
  produces hundreds of false "undefined" errors from missing generated files.
- `flutter test --update-goldens test/design_system` runs the real
  design-system widget tests; it is kept for convention, but there are **no
  golden baselines to update** (see §5c).

---

## 3. What to paste back if errors

Paste these into the next session (they are small):

1. `grep -c "error:" analyze.log` output
2. `grep "error:" analyze.log | head -20`
3. `tail -30 test.log`
4. If codegen fails: `tail -30 codegen.log`
5. If `pub get` fails: `tail -30 pubget.log` (dependency resolution issues)

---

## 4. Known risks (consolidated from all stage reports, ordered by severity)

### Tier A — can block the local run itself

1. **Generated code does not exist yet.** `drift_dev`, `riverpod_generator`,
   and `freezed` outputs (`*.g.dart`, `*.freezed.dart`) are committed nowhere
   (correctly gitignored). The tree does not compile until
   `dart run build_runner build --delete-conflicting-outputs` succeeds.
2. **Never-compiled surface.** All 359 `.dart` files were authored blind (no
   Flutter/Dart SDK in the authoring sandbox). Structural audits passed
   (import resolution, delimiter balance, symbol audits — see
   `docs/STAGE_2_1_PREFLIGHT.md`), but real analyzer/runtime issues are
   expected on first contact.
3. **Strict lints.** `very_good_analysis ^11.0.0` is enforced; expect lint
   findings, some possibly error-level, on first `flutter analyze`.
4. **`flutter_local_notifications` channel** uses `@mipmap/ic_launcher` with
   hardcoded id/name `downloads`/`Downloads` — verify the launcher icon
   resolves on a real Android device (degrades to no-op on failure).
5. **Drift migration 2→3** (`0003_downloads.dart`, additive) is
   integration-required — only exercised against a real DB at runtime.

### Tier B — functional gaps that surface after the run works

6. **Jamendo needs a user-registered `client_id`** (`JAMENDO_CLIENT_ID` in
   `.env`). The demo id is suspended (API code 11) and anonymous calls fail
   (code 5) — without your id the source returns the API's error to the UI.
7. **FMA cannot stream or download by design** — the download endpoint
   redirects to `/login` (account wall, live-verified). FMA ships as
   search + license-metadata only; Wavely does not bypass account walls.
8. **Per-source cache clearing is impossible** against the Stage 1.2 HTTP
   cache (`http_cache` keys are sha256(METHOD+URL), no source column).
   Only total-size + clear-all exists; an additive migration plan is sketched
   in `docs/STAGE_2_1_REPORT.md` §5.
9. **Folder template placeholder gaps:** `{year}` = `Track.addedAt.year`,
   `{trackNumber}` = constant `00` (Track entity has no release-year /
   track-number fields). `ArtistGeoResolver` maps MusicBrainz areas to
   continents via a static table — uncommon areas fall back to `Unknown`.
10. **Download file I/O is io-platform only** (conditional-export executor;
    the web arm throws, mirroring Stage 1.1's `source_file_stub.dart`).
11. **Spotify app-link host not registered** (`TODO(verify)` ×2 in
    `lib/features/discovery/spotify_metadata_adapter.dart`) — PKCE OAuth
    needs owner signing config / developer accounts; not doable from sandbox.
12. **Supabase/Telegram/AI features are inert without keys** — see §5d; the
    local player core keeps working regardless.
13. **Navidrome live contract test** (`navidrome_contract_test.dart`) is
    skip-guarded locally and only executes in CI / with docker compose up —
    it has never been executed anywhere yet.

### Tier C — documented degradations (cosmetic / graceful)

14. Deezer `/related` may be Access-Denied from some IPs (search works);
    discovery degrades gracefully.
15. Reddit may return an HTML bot page — client validates content-type and
    degrades.
16. Heartbeat mood exclusions are prompt-level only (no hard queue-time
    genre enforcement).
17. `setSpeed` remains state-only (engine contract has no speed surface).
18. Multi-tool-call turns replay one `tool_call_id` on the OpenAI path.
19. Parental whitelist has matcher+provider plumbing but no editor UI
    (CSV seeding of blocked words exists).
20. Remote plays without a matching local track are skipped on pull (no
    orphan rows; full cross-device history needs the accounts layer).
21. **No golden/pixel-regression coverage** — the 48-capture golden harness
    from the Stage 1.1 plan was intentionally not rebuilt (baselines cannot
    be authored without a real Flutter run). Re-add after first local run if
    wanted.

---

## 5. Expected first-run behavior (do not panic)

a. **Codegen output missing until `build_runner` runs.** Analyzing before
   codegen floods the console with `Undefined name '…'` / `*.g.dart` missing
   errors. This is expected; run codegen first (the copy-paste block does).

b. **`flutter analyze` may report lint findings** (`very_good_analysis` is
   strict). Lints are not failures — collect them, paste the error-level
   ones back, fix in a follow-up PR.

c. **Goldens: there are none.** No `matchesGoldenFile` call and no `.png`
   baseline exists in the tree (intentional — see KNOWN_LIMITATIONS_FINAL
   §2). `flutter test --update-goldens test/design_system` simply runs the
   design-system widget tests; it cannot "fix missing goldens" because the
   golden harness is absent. First-run failures here are ordinary widget-test
   failures, not golden mismatches.

d. **`.env` missing does NOT crash the app** — contrary to generic
   assumptions, `lib/core/config/env.dart` makes every key optional by
   design: values are compile-time `String.fromEnvironment` constants that
   default to empty, and feature flags (`hasSupabase`, `hasAiProvider`,
   `hasJamendo`, …) degrade gracefully (auth shows the disabled path, online
   sources hide, AI chat is unavailable). The local player core runs with
   **zero keys**. To enable extras:

   ```bash
   cp .env.example .env       # fill in what you have; all keys optional
   flutter run --dart-define-from-file=.env
   flutter test --dart-define-from-file=.env   # for key-dependent tests
   ```

e. **Navidrome contract tests skip silently** without the docker container
   running (see the optional extras in §2).

f. **First `flutter test` on a fresh clone** creates the SQLite DB at
   schemaVersion 3 directly (`from < 3` migration never fires on fresh DBs) —
   migration correctness is only exercised on upgraded installs.

---

## 6. Post-merge hygiene (do these now)

1. **Revoke the fine-grained PAT** used this session
   (GitHub → Settings → Developer settings → Fine-grained personal access
   tokens → delete the `Music_Wavely`-scoped token).
2. **Rotate any secrets ever pasted in chat**, if exposed:
   `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`,
   `GEMINI_API_KEY`, `OPENAI_API_KEY`, `TELEGRAM_BOT_TOKEN`,
   `SPOTIFY_*`, `DEEZER_*`. The repo itself contains none of these (only
   empty-value `.env.example`), so rotation is only needed if they were
   shared in conversation.
3. **Local clones hold the token in the remote URL**
   (`https://Dani-Devlop:<token>@github.com/...`). After revocation it is
   inert, but reset it anyway:
   `git remote set-url origin https://github.com/Dani-Devlop/Music_Wavely.git`
4. Future sessions must not need the PAT — all work is on `main`; clone and
   push as the owner normally would.

---

## 7. Owner next steps (when a machine is available)

1. Clone, run the §2 copy-paste block.
2. Fix-and-paste loop per §3 (expected to take 1–3 short sessions: codegen
   errors → analyzer errors → test failures).
3. After the suite is green: decide whether to green-light Stage 2.2
   (News, Telegram Mini App, PWA, desktop packaging, auto-updater) — it is
   the only stage that was never authored.
4. Revoke the token (§6.1).
