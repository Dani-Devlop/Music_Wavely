# Known limitations — final (Stage 1.1 + 1.2 rebuild)

Every item below was either fixed in this rebuild or consciously documented
as out of scope. Nothing here is hidden: each entry lists the reason it
remains open and what closing it would require.

## Fixed in this rebuild (no longer limitations)

1. **`AudioCensorExecutor` was referenced but never defined** — added the
   abstract seam class in `lib/features/parental/data/censor_service.dart`
   with the exact signature both conditional arms already implement.
2. **PIN hashing upgraded from plain sha256 to salted v2** —
   `lib/features/parental/data/pin_hash.dart` now stores
   `p2$<saltHex>$<sha256(salt:pin)>` with a 128-bit `Random.secure()` salt;
   `verifyPin` still accepts legacy v1 hashes so existing profiles keep
   working. Onboarding's PIN creation and the parental-screen gate both use
   the new API. (This closes the "plain sha256" limitation #5 from
   `docs/STAGE_1_2_REPORT.md`.)
3. **Two `TODO(verify)` response-shape comments closed with verified
   citations** — Gemini function-calling shape confirmed against
   ai.google.dev/gemini-api/docs/function-calling (`candidates[].content
   .parts[].functionCall{name,args}`); OpenAI tool-calls shape confirmed
   against the official OpenAI OpenAPI spec
   (`choices[].message.tool_calls[].function.{name,arguments}`).
4. **Test tree rebuilt** — the previous session's 74-file suite was lost
   (never pushed; unrecoverable from local git or the deleted remote
   branches). Re-authored: see the test inventory in this repo
   (`test/`), all marked "authored, awaiting local run".

## Remaining limitations (documented, out of scope for Stage 1.2)

1. **Spotify app-link host not registered** (`TODO(verify)` ×2 in
   `lib/features/discovery/spotify_metadata_adapter.dart`) — the OAuth
   redirect scheme+host must be registered in the Android manifest /
   Apple universal links before PKCE can complete. Requires the owner's
   signing config and developer accounts; not doable from a sandbox.
2. **Golden baselines not committed** — the design-system components are
   covered by 13 widget tests + `themes_test.dart`, but the 48-capture
   golden harness from the Stage 1.1 plan was intentionally NOT rebuilt:
   goldens fail without a baseline seeding step
   (`flutter test --update-goldens test/design_system`), which would break
   the "first local run is green" goal. Re-add after baselines are seeded
   on a real machine if pixel-regression coverage is wanted.
3. **Integration flow test not rebuilt** — the host-runnable
   scan→play→lyrics golden path documented in `docs/STAGE_1_1_REPORT.md`
   §test (integration/app_flow_test.dart) was not re-authored; its scope
   overlaps the unit suites and it needs a real device/emulator run to be
   meaningful (`integration_test/`).
4. **Heartbeat mood exclusions are prompt-level only** — heartbreak mood
   exclusions reach the model via the system prompt; hard genre
   enforcement at queue-build time is a follow-up (unchanged from
   `docs/STAGE_1_2_REPORT.md` limitation 1).
5. **Telegram flow uses magic-link `token_hash` + `verifyOtp`** — no
   direct JWT minting in the supabase-js admin API (unchanged; documented
   in the edge function).
6. **Deezer `/related` may be Access-Denied from some IPs** — search
   works; the discovery section degrades gracefully (unchanged).
7. **Reddit may return an HTML bot page** — client validates content-type
   and degrades (unchanged).
8. **Remote plays without a matching local track are skipped on pull** —
   no orphan rows; full cross-device history needs the accounts layer
   (unchanged).
9. **`setSpeed` remains state-only** — the engine contract has not grown a
   real speed surface since Stage 1.1 (unchanged).
10. **Multi-tool-call turns replay one tool_call_id on the OpenAI path** —
    acceptable for v1 chat usage (unchanged).
11. **Whitelist has matcher+provider plumbing but no editor UI** — the
    parental whitelist can be seeded (CSV import into blocked words is
    available) but there is no dedicated whitelist editor screen (unchanged).
12. **Everything in `lib/` and `test/` is "authored, awaiting local run"** —
    no Flutter SDK exists in the authoring sandbox; the owner must run
    `flutter pub get && dart run build_runner build
    --delete-conflicting-outputs && flutter analyze && flutter test
    --coverage` locally. Static checks performed here: every import
    resolves, every delimiter balances (interpolation-aware scan), every
    `extends`/`implements`/`catch on` type resolves to a lib definition,
    an external package symbol, or a Dart core type, and every
    `*Provider` referenced by tests exists in lib.

## Stage 2.2 additions (news, Telegram Mini App, PWA, packaging)

13. **iOS PWA background audio is unreliable** — Safari suspends
    `HTMLAudioElement` when the page loses focus; the Media Session API
    reduces but does not remove the problem. The dismissible iOS guidance
    banner points users at the Telegram Mini App instead.
14. **No remote-track download in the PWA** — the Stage 2.1 download
    executor is io-platform-only by design (conditional export); the web
    arm throws the documented `UnsupportedError`.
15. **Codec support varies by browser** — web playback depends on the
    browser's codec set (FLAC missing on old Safari, etc.); the engine
    surfaces `PlaybackState.error` and the UI shows the error path.
16. **No local file scan on web** — the library scanner's web arm is a
    stub (unchanged from Stage 1.1); the web build plays remote/streaming
    sources only.
17. **Telegram Mini App background audio pauses when leaving the app** —
    the Mini App webview suspends JS timers and audio when backgrounded;
    playback resumes on return. Documented in docs/TELEGRAM_MINIAPP.md.
18. **PWA icons are generated placeholders** (solid `#7C5CFF` with a white
    waveform, all 8 sizes) — the owner must replace them with real brand
    assets before release (docs/PACKAGING.md).
19. **MSIX is unsigned** (`sign: false` in `msix_config.yaml`) — the
    owner must provide a signing certificate; the release workflow
    packages but does not sign.
