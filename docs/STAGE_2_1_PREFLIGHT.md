# Stage 2.1 Pre-flight Report

Status: **PASSED** (structural verification only — no Flutter SDK in this sandbox;
`flutter analyze` / `flutter test` were NOT run, per Stage 2.1 Section 2 rules).

## 2.1 — Git state

- Working tree: fresh clone of `https://github.com/Dani-Devlop/Music_Wavely.git`,
  branch `main`, clean (`git status` empty).
- Remote default branch: `main` (API `GET /repos/Dani-Devlop/Music_Wavely` → 200,
  `default_branch: main`, `private: false`, `full_name: Dani-Devlop/Music_Wavely`).
- Branches on remote: `main` only (`GET /branches` → 200, single entry).
- main HEAD sha: `e9b24604868a82525014c5c2a2f1e1c88d308b94`
- HEAD commit (git level): author `Dani <daniel841384@gmail.com>`,
  subject `Stage 1.1 + 1.2 source tree`.

  Note: GitHub rewrote the author at squash-merge time to the account's public
  noreply-adjacent email; the GitHub-side author login for this commit is
  `Dani-Devlop`. The literal `Dani-Devlop <Dani-Devlop@users.noreply.github.com>`
  authorship is on the pre-squash feature commit (dc09b30), documented in the
  Stage 1 session worklog. This is recorded here because the Stage 2.1 identity
  law requires the honest state, not a convenient one.

## 2.2 — Import resolution

Script from Section 2.2 run unmodified over `lib/` and `test/`:

```
OK: all imports resolve
```

(0 unresolved imports; exit 0.)

## 2.3 — Symbol audit

Raw command from Section 2.3 output 18 names (CacheProvider, CountProvider,
DeviceInfoProvider, DirProvider, EngineProvider, FailingProvider,
FollowStateProvider, InfoProvider, LauncherProvider, ManagerProvider,
PrefsProvider, RepositoryProvider, ScannerProvider, ScriptedProvider,
ServiceProvider, StateProvider, StoreProvider, TransparencyProvider).

Investigation (pasted evidence in session log):

1. The raw grep `[A-Z][A-Za-z0-9_]*Provider\b` has **no left word boundary**, so
   it matched mid-word fragments of lowerCamelCase identifiers, e.g.
   `EngineProvider` inside `playbackEngineProvider`
   (`lib/playback/engines/engine_factory.dart:13`:
   `final playbackEngineProvider = Provider<PlaybackEngine>((ref) {`),
   `PrefsProvider` inside `sharedPrefsProvider`, `CacheProvider` inside
   `lyricsCacheProvider` (`lib/features/lyrics/data/lyrics_cache.dart:78`),
   `TransparencyProvider` inside `reduceTransparencyProvider`
   (`lib/features/settings/data/settings_provider.dart:196`). All 18 fragments
   resolve to real declarations once the left boundary is enforced.
2. Re-audit with proper identifier boundaries found 31 provider identifiers
   referenced by tests; 10 required manual resolution, all confirmed declared:
   - `DeviceInfoProvider` — typedef in both conditional arms
     (`lib/core/utils/platform_utils_io.dart:25`,
     `lib/core/utils/platform_utils_web.dart:20`).
   - `defaultDeviceInfoProvider` — top-level function
     (`lib/core/utils/platform_utils_web.dart:80`).
   - `cacheDirProvider` — constructor-injected instance field
     (`lib/features/parental/data/censor_service.dart:52`).
   - `embeddedProvider` — `static const String embeddedProvider = 'embedded'`
     (`lib/data/local/db/daos/lyrics_dao.dart:16`).
   - `hasAiProvider` — declared in `lib/core/config/env.dart`.
   - `ScriptedLyricsProvider` — test-local fake (test tree declaration).
   - `reduceTransparencyProvider` — type-first style
     (`lib/features/settings/data/settings_provider.dart:196`).
   - `settingsProvider` — `lib/features/settings/data/settings_provider.dart`.
   - `sharedPrefsProvider` / `packageInfoProvider` — **riverpod_generator**
     variables: source functions `SharedPreferences sharedPrefs(SharedPrefsRef
     ref)` (`lib/features/settings/data/settings_provider.dart:19`) and
     `Future<PackageInfo> packageInfo(PackageInfoRef ref)`
     (`lib/app/app_providers.dart:15`) with `part 'app_providers.g.dart'`.
     The `<name>Provider` variables are emitted into `.g.dart` by
     `dart run build_runner build` (owner local-verification step 2). The repo
     intentionally ships 0 committed `.g.dart` files (no SDK here); this is the
     documented "authored, awaiting local run" contract from Stage 1.1/1.2.

**Verdict: PASS** — every provider referenced by tests resolves either to a
source declaration or to a documented build_runner-generated symbol.

## Inventory

| Metric        | Count                            |
| ------------- | -------------------------------- |
| lib files     | 209                              |
| lib lines     | 22,868                           |
| test files    | 98                               |
| test lines    | 20,252                           |

## Integration seams located (for Stage 2.1, additive use only)

- `SourceProvider` contract: `lib/domain/repositories/source_provider.dart`
  (`id`, `displayName`, `supportsStreaming/Download/Search`, `search()`,
  `resolveStream()`, `download()`, `getMetadata()`; `File` via conditional
  export `source_file.dart`).
- Entities: `Track` (freezed, has `sourceId`/`sourceTrackId`/`format`/`filePath`;
  **no ISRC field** — dedupe uses title+artist+Levenshtein),
  `StreamUrl`, `AudioQuality { low, medium, high, lossless }`
  (`lib/domain/entities/source_types.dart`).
- `RateLimiter`: `lib/data/remote/metadata_http.dart:32` (`waitTurn()`).
- Drift: `AppDatabase` schemaVersion 2, migrations
  `lib/data/local/db/migrations/000{1,2}*.dart` (repo convention is
  `db/migrations/`, so Migration0003 lands there).
- Search: `lib/features/search/presentation/` (providers + screen, FTS local
  only) — extended additively with a Library/Online scope switch.
- `SourceBadge`: `lib/design_system/components/source_badge.dart`
  (already knows subsonic/navidrome/jamendo/archive icons).
- Settings screen: `_SectionGroup`-based (`Appearance/Playback/Storage/More/
  About`); additive groups appended, existing rows untouched.
- No `ArtistCountryResolver` exists on main (Stage 1.2 discovery ships
  `discovery_service.dart` + MusicBrainz client but no country resolver) — the
  download folder template gets a new `ArtistGeoResolver` wrapper documented as
  NEW code, not "existing".
- `flutter_local_notifications` is in pubspec but has no wrapper yet — a
  downloads notifier interface + plugin-backed impl is added behind an
  interface so tests use a fake.

## Live endpoint verification (sandbox curl, recorded in METADATA_SOURCES.md)

- Jamendo `GET /v3.0/tracks/?format=json&limit=2` (no client_id) → HTTP 200,
  body `headers.status=failed, code=5` (invalid client id). Demo id `56d30c95`
  → `code=11` "Suspended Application". ⇒ provider requires a user-registered
  client_id; fixtures used in tests.
- archive.org `advancedsearch.php` (audio mediatype) → 200 with docs
  (identifier/title/creator/year). `metadata/{id}` → 200 with files array.
  `download/{id}/{file}` standard pattern.
- FMA legacy JSON API (`/api/trackSearch`, `/api/get/tracks.json`) → 404 (dead).
  Search HTML `GET /search?quicksearch=...` → 200 (134 KB) with parseable
  `/track/<slug>` anchors, artist anchors, durations and
  `data-url=".../downloadOverlay/"` download links. robots.txt: no
  `User-agent: *` block (specific AI bots only) — provider still rate-limits
  1 req/2 s.

Proceeding to Section 3 with: additive-only integration, no rewrites of
Stage 1.1/1.2 files except the required Drift registration of the new table
(bump schemaVersion 2 → 3 + Migration0003 call, appended additively).
