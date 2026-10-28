# Test Coverage Audit — Stage 3

Date: 2025-10-28 · Scope: `main @ 1cd90ca` + the Stage 3 fix pass.

## Method

Filename-based mapping (`lib/**/foo.dart` ↔ `test/**/foo_test.dart`),
excluding generated files (`.g.dart` / `.freezed.dart` / `.mocks.dart`).
Case counts are static (`test(`/`testWidgets(` occurrences).

**Counting caveats (important):**
- Loop-driven widget suites under-count: e.g. `chip_filter_test.dart`
  declares ONE `testWidgets` but runs it 4× (2 themes × 2 selections). The
  "thin" tier therefore over-reports; after manual inspection all 9 thin
  files are loop-driven design-system smoke suites (2-8 real cases).
- Group-named test files under-count coverage: e.g. `test/core/
  extensions_test.dart` covers `string_x.dart` + `duration_x.dart` +
  `color_x.dart`, and `test/playback/engines_test.dart` covers several
  engines. The matrix maps by filename only, so some "untested" files DO
  have indirect coverage. Items listed untested below were checked
  manually.

## Totals

| Metric | Before Stage 3 | After Stage 3 |
|---|---|---|
| lib dart files (non-generated) | 264 | 264 |
| test files | 117 | **120** (+3) |
| static test cases | 1087 | **1114** (+27) |
| well-tested lib files (≥3 mapped cases) | 99 | **102** |
| thin (1-2 mapped cases) | 9 | 9 |
| untested (no same-name test file) | 156 | **153** |

Golden tests: still zero (unchanged; `matchesGoldenFile` nowhere).

## Untested bucket breakdown (153 files)

| Bucket | Count | Assessment |
|---|---|---|
| Drift table definitions (`tables/`) | 16 | Schema declarations — exercised through the DAO tests; no direct unit surface. Acceptable. |
| Drift migrations (`migrations/`) | 4 | Schema-only; exercised by DAO tests against a native in-memory DB. Acceptable. |
| Freezed entities (`entities/`, `settings.dart`) | 11 | Data classes covered indirectly wherever they are constructed; unit tests would duplicate compiler guarantees. Low value. |
| Conditional exports / platform stubs (`*_stub`, `*_io`, `*_web`, `update_platform`, `cache_cleaner_*`, `library_scanner_provider_*`, `source_file_*`) | 30 | Seam files; the injectable arm is tested through the interface, the platform arm needs devices. Acceptable by design. |
| Riverpod providers / composition roots | 22 | Binding code; needs the SDK + provider containers. Owner-run widget tests cover them indirectly. |
| Screens & widgets without dedicated tests | 19 | UI; best served by the integration suite below. |
| Other logic (engines, bootstrap, tokens, adapters) | 51 | Mixed — see the priority list below. |

## Tests authored in this pass (authored, awaiting local run)

1. `test/features/news/data/news_category_test.dart` — 15 cases: classifier
   ordered rules, word-boundary semantics ("said" ≠ "ai"), phrase
   substrings, education-before-production ordering, plural-token
   non-matching, default bucket, storage-name round trips, label
   uniqueness.
2. `test/features/ai_chat/data/provider_http_test.dart` — 7 cases: retry
   schedule (500→200, 429), no-backoff on immediate success, exhausted-5xx
   last-response contract, ClientException retry + friendly failure,
   per-attempt timeout (SEC-5) with backoff accounting.
3. `test/features/downloads/data/download_events_test.dart` — 5 cases:
   event defaults/payload, const construction, DownloadStatus lifecycle +
   storage-name contract.
4. `test/features/parental/pin_hash_test.dart` — **updated** for the SEC-11
   v3 format: p3 iterated-hash verification, fresh salts, p2/v1 legacy
   acceptance, garbage rejection, shape boundaries (was v2-only).

All new tests are pure Dart/Flutter-test (mocktail-free; `http/testing`
MockClient only) so they exercise production paths without platform
channels.

## Priority list for the owner (highest-value uncovered logic)

1. `lib/features/telegram/telegram_theme_adapter.dart` — pure mapping,
   ideal unit-test target after the mini-app lands.
2. `lib/features/news/data/news_article.dart` — `toCompanion` mapping
   (one drift-native test mirrors `news_dao_test.dart`).
3. `lib/features/onboarding/data/onboarding_state.dart` — draft defaults +
   language reorder invariants.
4. `lib/features/settings/data/cache_cleaner_io.dart` — temp/cache deletion
   rules (needs path_provider fakes).
5. `lib/data/sync/supabase_sync_backend.dart` — payload-shape contract vs
   the (now defaulted) `user_id` columns; best as a PostgREST-shaped
   contract test with a recorded-response fake.
6. Design-system tokens (`colors.dart`, `typography.dart`) — constant
   snapshot tests; cheap regression nets.

## Integration coverage (gaps → authored specs, awaiting local run)

These four end-to-end flows have NO automated coverage. They need the SDK
(flutter_tester + fakes for engines/platform channels). Specs so the owner
(or a follow-up stage) can author them locally:

1. **onboarding → scan → play → lyrics → queue**: pump `OnboardingFlow`,
   finish with defaults; inject a `ScanLibrary` over a fixture folder
   (memory FS); assert tracks appear; launch playback through the real
   `QueueManager` with a fake `PlaybackEngine`; assert lyrics load from the
   seeded `lyricsDao` row and queue restore round-trips.
2. **download → offline → replay**: enqueue a track against a local HTTP
   fixture server; await `completed`; point the source resolver at an
   unreachable endpoint; assert the local file path is what the queue loads
   (provenance sidecar present).
3. **parental block → skip**: seed a blocked word matching track B; queue
   A/B/C with a fake engine; assert the preload hook emits `skip` for B and
   the queue rests on C with an audit row.
4. **AI chat → build queue**: fake `AiProvider` returning one
   `search_library` tool call + a final answer referencing a real track id;
   assert the executor resolves it from the library and the queue is set.

## Verification

Counts and mappings were produced by script (`coverage_matrix.py` logic)
against the actual tree; new test files import only existing, resolved
packages (verified by the Stage 3 import scanner). `flutter test
--coverage` locally is the true gate — see `docs/STAGE_3_REPORT.md` §9.
