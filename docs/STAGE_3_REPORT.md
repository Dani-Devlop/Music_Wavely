# Stage 3 Report — Comprehensive Audit

Date: 2025-10-28 · Branch: `fix/stage-3-audit` (based on `main @ 1cd90ca`,
the squash-merged Stage 2.2) · Author: Dani-Devlop
\<Dani-Devlop@users.noreply.github.com\> · **All code authored, awaiting
local run — no Flutter/Dart SDK exists in the audit sandbox.**

## 1. Pre-flight state

- PR #4 (Stage 2.2) verified mergeable and squash-merged by the owner's
  instruction BEFORE this audit began; branch `feat/stage-2.2` deleted.
- Audit ran on a FRESH clone of merged main (`1cd90ca`): 466 tracked files
  (lib 263 dart / test 127 / docs 20 / supabase 5).

## 2. Static analysis (scripts, no SDK)

| Check | Result |
|---|---|
| Import resolution (391 dart files) | 27 unresolved — **all** are `part 'codegen'` directives that materialize on the first `build_runner` run (expected, documented). `package:meta` (5 files) and `package:fake_async` (3 test files) were real missing declarations → **fixed in pubspec**. |
| Circular dependencies (lib graph, parts merged) | 4 — two are the intentional conditional-export idiom (`telegram_bridge`, `censor_executor`), one is the standard drift pattern (app_database ↔ DAOs), one is the ai_chat provider triangle (`ai_provider ↔ ai_tools ↔ gemini/openai`; legal Dart, lazy top-levels). All **documented, none fixed** — breaking them would touch codegen-bearing files for zero runtime benefit. |
| Delimiter balance (interpolation-aware scanner, 391 files) | **0 issues** (391/391 clean), before and after the fix pass. |
| Null-safety smells | 0× `as dynamic`, 0× `?? null`, 0× `!!`; 161 `!` operators total, max 11 in one file (`news_service.dart` — parser edge guards). Clean. |
| Dead code / unused imports | 94 heuristic candidates; after manual verification (export barrels, conditional exports, codegen symbols) **5 confirmed true unused imports removed** (settings_screen ×3, library_screen ×1, news_screen ×1 — go_router navigation left them behind). The rest are false positives from missing codegen parts; `flutter analyze` will arbitrate locally. |
| Async correctness | Every `StreamSubscription` file contains `.cancel()`; every `Timer.periodic` file contains `.cancel()`; 0 heuristic async-without-await findings. One REAL async bug found by manual review: BUG-1 (missing `await` — compile error). |

## 3. Security audit

Full detail: `docs/SECURITY_AUDIT.md` (SEC-1 … SEC-20 + 11 clean areas).
Counts: **CRITICAL 0 · HIGH 0 · MEDIUM 8 · LOW 9 · INFO 3.**
- Fixed: 14 (SEC-3,4,6,7,8,9,10,11,12,13,14,16,17,19)
- Partially fixed: 2 (SEC-5 timeouts — streaming download & auth RPC
  documented; SEC-15 — checksums added, pinning/update-verify documented)
- Documented (owner decisions / needs-SDK): 4 (SEC-1 session storage,
  SEC-2 bot-token-derived passwords, SEC-18 compile-time secrets, SEC-20
  delete-account RPC + unwired mini-app auth)
- RLS: every remote table verified owner-locked (clean). Edge-function
  HMAC: timing-safe, 1-h window, no secret logging (clean).

## 4. Logic bug hunt

Full detail: `docs/BUG_FIXES.md` (BUG-1 … BUG-15 + 9 clean areas).
Counts: **HIGH 3 · MEDIUM 8 · LOW 4.**
- Fixed: 14 — including **two compile blockers** (BUG-1 missing `await` in
  sync pull; BUG-2 out-of-scope variable in queue manager) and the sync
  auth gap (BUG-3: sync never authenticated, pushes always 403'd).
- Documented: 1 (BUG-8 re-scan identity/pruning — needs SDK + design).
- Owner policy decision flagged: BUG-9 "block instead of play uncensored"
  switch.

## 5. Coverage audit

Full detail: `docs/COVERAGE_AUDIT.md`.
- Before → after: 117 → **120 test files**, 1087 → **1114 cases**,
  well-tested lib files 99 → **102**.
- Authored (awaiting local run): news classifier suite (15 cases),
  provider retry/timeout suite (7), download event contract (5), PIN hash
  v3 rewrite of the existing suite.
- Untested buckets quantified (drift tables, conditional exports, provider
  bindings, screens) + 4 integration-flow specs written for the owner.

## 6. Fix pass by priority

| Priority | Items | Status |
|---|---|---|
| P0 compile blockers | BUG-1, BUG-2 | fixed |
| P1 security CRITICAL/HIGH | — (none existed) | n/a |
| P1 security MEDIUM | SEC-3,4,6,7,8 (+SEC-5 timeouts, SEC-1/2 docs) | fixed / documented |
| P2 logic | BUG-3..7, 9..11, 12..15 | 13 fixed, BUG-8 documented |
| P3 test gaps | 3 new suites + PIN suite rewrite | authored |
| P4 docs | 4 audit docs + CHANGELOG + this report | done |

Every applied fix is marked with a `Stage 3 audit (SEC-*|BUG-*)` comment at
the edit site.

## 7. Documented-not-fixed (explicit list)

- SEC-1 secure session storage (needs resolved-version API verification)
- SEC-2 per-user random password instead of bot-token derivation
- SEC-18 compile-time key extraction (process rule)
- SEC-20 `delete_account` RPC + wiring the mini-app session applier
- BUG-8 re-scan identity & pruning design
- Import cycles ×4 (accepted idioms), codegen `part` resolution (first
  local build), remaining 89 unverified unused-import candidates

## 8. Validation results

Re-run AFTER the fix pass:
- Import scanner: 27 unresolved (all codegen parts — meta/fake_async now
  resolve) · **OK**
- Delimiter scanner: 391/391 files balanced · **OK**
- Secret scan (`ghp_`/`github_pat_`/`sk-`/`AIza`/private keys, lib+test+
  supabase+docs+web+workflows+yaml+md): **clean**
- Referenced tests exist: all four touched/new test files present on disk
  and import-resolvable · **yes**
- Additivity: changes touch `lib` (13 files), `test` (2 rewritten/3 new),
  `pubspec.yaml`, `supabase` (1 new migration, 2 edge functions,
  config.toml), workflows (2), compose file, docs, CHANGELOG — no file was
  deleted; Stage 1/2 behaviour changes are the audited fixes only.

## 9. Owner local verification (must run before merging)

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze 2>&1 | tee analyze.log
flutter test --coverage 2>&1 | tee test.log
grep -c "error:" analyze.log || true
tail -30 test.log
# expect: analyze errors only for pre-existing codegen-unrelated issues
# (there should be none); tests: 1114+ cases, PIN/news/provider suites green
```

Paste back `grep -c "error:" analyze.log` and the test tail for close-out.

## 10. Commit & PR

- Branch: `fix/stage-3-audit` → `main`, opened as a PR, **not merged**
  (owner reviews SEC-* findings first — especially SEC-1/SEC-2 and the
  BUG-9 policy decision).
- Commit identity: Dani-Devlop <Dani-Devlop@users.noreply.github.com>
  (verified via API after push).
- The GitHub token used by this automation must be revoked after review.
