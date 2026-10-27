# Stage 1.1 — Audit & Fix Report (Task A)

> Produced before Task 4 (settings/app shell). Two parallel audit agents
> (A1: core + design system + themes; A2: data + features + playback + lyrics)
> inspected every file written in Tasks 1–3-c by full read, applied an
> inspection-level fix pass, and re-verified. The orchestrator then closed the
> remaining cross-cutting items. **No Dart/Flutter SDK exists in the authoring
> sandbox** — everything below is verified by inspection, doc citation, and
> scripted checks (import resolution, part-directive existence, delimiter
> balance), NOT by `flutter analyze`/`flutter test`. Local run is mandatory
> (see STAGE_1_1_REPORT.md §7).

## Orchestrator-level fixes (after A1 + A2)

| # | File(s) | Issue → Fix |
|---|---|---|
| O1 | `lib/design_system/components/wavely_cover{,_io,_stub}.dart` (new), `track_tile/mini_player/artist_circle/album_card.dart` | Unconditional `dart:io` + `Image.file` broke web compilation of 4 design components → conditional-export `wavelyCoverProvider(String?)` hub (io: `FileImage`, web: null → fallback placeholder). Pattern mirrors `local_cover` trio from 3-b. |
| O2 | `lib/domain/repositories/source_file{,_io,_stub}.dart` (new), `source_provider.dart` | `SourceProvider.download` signature used `dart:io` File unconditionally → conditional export; web arm is a compile-only stub that throws if invoked (Stage 1.1 ships no SourceProvider impls). |
| O3 | `test/player/{now_playing_screen,queue_sheet,mini_player_host}_test.dart` | Relative test-to-test imports (`../playback/fake_playback_engine.dart`) are the only valid form for `test/` helpers (package imports cannot resolve into `test/`) → documented + `// ignore_for_file: always_use_package_imports` added per file. |
| O4 | whole tree | Scripted check: **384 `package:wavely/*` imports — 0 unresolved; 0 relative imports in lib/; all non-generated `part` directives point to existing files**; delimiter balance verified on all files touched this session. |

## Part 1 — Core, entities, design system, themes (Task 2 + 3-a scope)

# Stage 1.1 Audit — Part 1 (core + design system)

Task ID: A1 · Scope: files written by Task 2 + Task 3-a + their tests.
Verification method: inspection only (no Flutter/Dart SDK in sandbox). External
API facts cited against pub.dev / api.dart.dev / api.flutter.dev where relevant.

---

## Inventory

Status legend: complete = implementation + tests present; stub = intentional
placeholder; broken = would not compile/test as-is; missing-test = no test file.

### lib/core (Task 2)

| path | lines | purpose | status |
|---|---|---|---|
| lib/core/errors/failures.dart | 37 | freezed sealed `Failure` (network/storage/permission/parsing/unknown, each `{required String message, Object? cause}`) | complete |
| lib/core/errors/result.dart | 57 | freezed sealed `Result<T>` (`Success`/`Err`) with hand-written `isSuccess/isErr/fold/map/getOrElse/flatMap`; freezed map/when disabled via `@Freezed(map: FreezedMapOptions.none, when: FreezedWhenOptions.none)` | complete |
| lib/core/constants/app_constants.dart | 56 | AppConstants (animationMs, blur budgets, touchTargetMin 44, trackTileCoverSize 40, persist keys, sleep presets, …) | complete |
| lib/core/extensions/color_x.dart | 23 | ColorX: lighten/darken/isDark/toHex (uses 3.35 `toARGB32()`) | complete |
| lib/core/extensions/duration_x.dart | 38 | DurationX: hm / hmOrDash / digitalClock | complete |
| lib/core/extensions/extensions.dart | 7 | barrel (color_x, duration_x, string_x) | complete |
| lib/core/extensions/string_x.dart | 39 | StringX: isBlank / sanitized (control+illegal chars, collapse, 120 cap, `untitled` fallback) | complete |
| lib/core/settings/settings_store.dart | 36 | abstract SettingsStore (write/read<T>) + InMemorySettingsStore | complete |
| lib/core/utils/logger.dart | 62 | sanitizeForRelease / prepareLogMessage (@visibleForTesting) / AppLogger (d/i/w/e) | complete |
| lib/core/utils/platform_utils.dart | 15 | conditional-export barrel (io/web) — **rewritten in this audit**, see Fixes | complete |
| lib/core/utils/platform_utils_io.dart | 110 | NEW io arm (was the old platform_utils.dart body): PlatformUtils, DeviceInfoSnapshot/Provider, isLowEndDevice, defaultDeviceInfoProvider (device_info_plus 13.x: `physicalRamSize`, `version.sdkInt`, `Platform.numberOfProcessors`) | complete |
| lib/core/utils/platform_utils_web.dart | 87 | NEW web arm: same public surface without dart:io (isMobile/isDesktop=false, defaultDeviceInfoProvider→null per documented io-arm contract) | complete |
| lib/core/utils/stable_hash.dart | 37 | FNV-1a 64 stableHash + hashList | complete |

### lib/domain (Task 2; usecases are Task 3-b, out of A1 scope)

| path | lines | purpose | status |
|---|---|---|---|
| lib/domain/entities/track.dart | 45 | freezed Track (+ `Track._`, localSourceId, displayDuration/artistOrUnknown/isLocal) | complete |
| lib/domain/entities/album.dart | 17 | freezed Album | complete |
| lib/domain/entities/artist.dart | 14 | freezed Artist | complete |
| lib/domain/entities/playlist.dart | 17 | freezed Playlist | complete |
| lib/domain/entities/play_event.dart | 17 | freezed PlayEvent | complete |
| lib/domain/entities/user_profile.dart | 14 | freezed UserProfile | complete |
| lib/domain/entities/source_types.dart | 19 | AudioQuality/SourceKind enums + freezed StreamUrl | complete |
| lib/domain/entities/lyrics_entities.dart | 34 | freezed LyricWord/LyricLine/LyricsResult | complete |
| lib/domain/entities/scan_events.dart | 30 | freezed sealed ScanEvent (scanStarted/trackFound/progress/completed/error) | complete |
| lib/domain/entities/entities.dart | 11 | entities barrel | complete |
| lib/domain/repositories/source_provider.dart | 29 | abstract SourceProvider (see Consistency 2b) | complete |
| lib/domain/repositories/lyrics_provider.dart | 8 | abstract LyricsProvider (id, fetch) | complete |
| lib/domain/usecases/scan_library.dart | 472 | Task 3-b file — inventoried only, audited by part-2 | out of A1 scope |
| lib/domain/usecases/search_local.dart | 101 | Task 3-b file — inventoried only, audited by part-2 | out of A1 scope |

### lib/playback (contract file only)

| path | lines | purpose | status |
|---|---|---|---|
| lib/playback/engines/playback_engine.dart | 29 | PlaybackState/RepeatMode enums + abstract PlaybackEngine (Task 2, untouched by 3-c — verified) | complete |

### lib/design_system

| path | lines | purpose | status |
|---|---|---|---|
| tokens/colors.dart | 67 | WavelyAccent enum + WavelyAccentX.colors + AccentColors (purple/green) + WavelyDarkColors/WavelyLightColors | complete |
| tokens/typography.dart | 55 | WavelyTypography (Sora headings/Inter body ramp + timerTabular) | complete |
| tokens/spacing.dart | 10 | Spacing xs…huge (4/8/12/16/24/32/48) | complete |
| tokens/radii.dart | 20 | AppRadii sm/pill + bSm/bMd/bLg/bXl/bPill | complete |
| tokens/shadows.dart | 21 | WavelyShadows dark/light | complete |
| tokens/blur.dart | 9 | WavelyBlur surface/elevated (mirrors AppConstants budgets) | complete |
| tokens/durations.dart | 17 | WavelyDurations fast/normal/slow + standard curve | complete |
| themes/semantic_extension.dart | 172 | WavelySemanticColors ThemeExtension (dark/light factories, lerp, copyWith, ==/hashCode) + `context.wavelyColors` | complete |
| themes/app_theme.dart | 104 | WavelyThemes.light/dark(accent) → _build (ColorScheme.fromSeed + overrides + registered extension) | complete |
| themes/theme_provider.dart | 113 | freezed ThemeSettings + ThemeSettingsNotifier (StateNotifier) + settingsStoreProvider + themeSettingsProvider | complete |
| components/glass_card.dart | 116 | GlassCard ConsumerWidget (BackdropFilter / reduceTransparency fallback, onTap InkWell, elevated shadow outside ClipRRect) | complete |
| components/track_tile.dart | 183 | TrackTile + public WavelyCoverFallback (merged semantics, selected key, 40px cover, ≥44 row) | complete |
| components/artist_circle.dart | 67 | ArtistCircle (Tooltip+Semantics, max(2*radius,44) touch) | complete |
| components/album_card.dart | 78 | AlbumCard (aspect-1 cover, InkWell) | complete |
| components/mini_player.dart | 166 | MiniPlayer (GlassCard elevated, _MiniProgressBar fraction guard, 44dp IconButtons) | complete |
| components/section_header.dart | 56 | SectionHeader (44 min row, action only when label+callback) | complete |
| components/chip_filter.dart | 88 | ChipFilter (44 tap area via ConstrainedBox+Align heightFactor:1) | complete |
| components/shimmer.dart | 96 | Shimmer (repeating 1200ms sweep, white 8% band) + ShimmerBox | complete |
| components/empty_state.dart | 83 | EmptyState (64px accent circle, optional CTA ≥44) | complete |
| components/error_state.dart | 76 | ErrorState (error variant, mandatory Retry ≥44) | complete |
| components/progress_ring.dart | 43 | ProgressRing (clamp, null→indeterminate, 'Loading' semantics) | complete |
| components/explicit_badge.dart | 42 | ExplicitBadge (16px 'E', merged semantics key) | complete |
| components/source_badge.dart | 61 | SourceBadge (icon map + 'Metadata only'/​'Source: <id>' tooltip) | complete |
| components/components.dart | 18 | components barrel (alphabetical) | complete |
| design_system.dart | 16 | design-system barrel (components + themes + tokens) | complete |

### Tests

| path | lines | purpose | status |
|---|---|---|---|
| test/core/result_test.dart | 83 | Result branches/map/flatMap | complete |
| test/core/failures_test.dart | 60 | exhaustive sealed switch + message/cause | complete |
| test/core/extensions_test.dart | 96 | DurationX/StringX/ColorX | complete |
| test/core/logger_test.dart | 42 | sanitize + kDebugMode pass-through + singleton | complete |
| test/core/platform_utils_test.dart | 67 | isLowEndDevice matrix + PlatformUtils.isWeb | complete |
| test/design_system/themes_test.dart | 100 | 4 theme factories + context.wavelyColors + lerp + ThemeSettingsNotifier roundtrips | complete |
| test/design_system/components/* (13 files) | 970 | 1:1 widget test per component (glass_card, track_tile, mini_player, chip_filter, empty_state, error_state, section_header, shimmer, artist_circle, album_card, progress_ring, explicit_badge, source_badge) | complete |
| test/goldens/components_goldens.dart | 156 | golden_toolkit DeviceBuilder; 12 components × 4 combos (shimmer excluded, documented in header) | complete (baselines not yet generated — see Known gaps) |

Total scope files inspected: 71. All 71 pass a balanced-delimiter/string-comment
scan; every file additionally read top-to-bottom.

---

## Consistency findings

### (a) Import paths — PASS
- Scripted check over the whole scope: every `package:wavely/...` import
  resolves to an existing file (re-run after the platform_utils fix: ALL OK).
- Zero relative imports anywhere in scope (barrel `export` statements are
  relative, which is not covered by VGA-11.0.0's `always_use_package_imports` —
  verified against the dart lint source: the rule only registers
  `ImportDirective`, not `ExportDirective`).
- `analysis_options.yaml` (Task 1) disables `public_member_api_docs` and
  `lines_longer_than_80_chars`; all style choices in scope conform to the
  remaining VGA-11.0.0 rules (verified `always_use_package_imports`,
  `avoid_catches_without_on_clauses`, `avoid_types_on_closure_parameters`,
  `directives_ordering`, `prefer_int_literals` in the 11.0.0 lint list).

### (b) Section 5 abstractions — PASS
- `SourceProvider` (source_provider.dart): id/displayName/supportsStreaming/
  supportsDownload/supportsSearch, `search(String q, {int limit = 20})`,
  `resolveStream(Track t) → Future<StreamUrl>`,
  `download(Track t, {required String targetPath, required AudioQuality quality}) → Future<File>`,
  `getMetadata(String sourceTrackId) → Future<Map<String, dynamic>>`. Matches
  Master Context exactly (dart:io File + web caveat documented in-file).
- `LyricsProvider` (lyrics_provider.dart): `id` + `fetch(Track) → Future<LyricsResult?>`. Match.
- `PlaybackEngine` (playback_engine.dart): `load(Track, {Duration? startAt})`,
  `play/pause/seek(Duration)`, `positionStream/stateStream`,
  `setQueue(List<Track>, {int startIndex = 0})`, `dispose`. Match; file untouched by 3-c as required.

### (c) Token exclusivity — PASS
Scripted greps over scope (excluding tokens/**):
- `Color(0x` / `Color.fromRGBO` → only tokens/colors.dart.
- `EdgeInsets.*` → only with Spacing.* token values (mini_player.dart:50,
  track_tile.dart:97, section_header, chip_filter all use Spacing tokens).
- `BorderRadius.circular` → only via AppRadii getters; documented private-const
  exception: explicit_badge.dart `_badgeCornerRadius = 4` (in-file doc).
- `TextStyle(` → only inside WavelyTypography (the token itself).
- `ImageFilter.blur` → only glass_card.dart (the sanctioned blur surface).
- `Duration(milliseconds:` → durations.dart (via AppConstants) and shimmer's
  documented `_ShimmerTiming.periodMs = 1200` private const.
Documented private metrics match the 3-a worklog list (64/32 circles, 16 chip
icon, 2 hairline, 1200ms/8% shimmer). No unexplained magic values found.

### (d) Riverpod inventory — DOCUMENTED (no refactor)
Scope contains exactly 2 providers, both manual (no @riverpod codegen anywhere
in scope; riverpod_annotation is pinned in pubspec but unused here):
| provider | file | kind |
|---|---|---|
| `settingsStoreProvider` | lib/design_system/themes/theme_provider.dart:105 | `Provider<SettingsStore>` (manual) → `InMemorySettingsStore()` default |
| `themeSettingsProvider` | lib/design_system/themes/theme_provider.dart:110 | `StateNotifierProvider<ThemeSettingsNotifier, ThemeSettings>` (manual) |
Downstream (3-b/3-c) are also manual providers; consistent mix. Task 4 must
override `settingsStoreProvider` (SharedPreferences store) and may override
`themeSettingsProvider` — both live in the SAME file (documented for Task 4).

### (e) Themes — PASS
- 4 ThemeData factories exist as light/dark × purple/green via
  `WavelyThemes.light(accent)` / `WavelyThemes.dark(accent)` → `_build`.
- `WavelySemanticColors extends ThemeExtension<WavelySemanticColors>` with
  `lerp` (covariant, null-safe), `copyWith`, `==`/`hashCode` (Object.hash over
  all 13 fields) — all present.
- `context.wavelyColors` getter exists (semantic_extension.dart:169).
- Flutter 3.35 API re-verified against api.flutter.dev (current stable docs):
  `ThemeData.appBarTheme` is `AppBarThemeData`, `cardTheme` is `CardThemeData`,
  `inputDecorationTheme` is `InputDecorationThemeData`,
  `ColorScheme.copyWith(surface:)` exists — app_theme.dart uses all correctly.

### (f) Freezed — PASS
- 12 files use `@freezed`; all 12 `part 'x.freezed.dart'` names match the file
  base names exactly (scripted check). Part files themselves are pending
  build_runner (documented project-wide; no .freezed.dart committed by design).
- `sealed` keyword present on Failure, Result<T>, ScanEvent.
- Private ctors present exactly where helpers/private-ctor patterns need them:
  `Failure._()`, `Result._()`, `ScanEvent._()`, `Track._()`.
- `@Freezed(map: FreezedMapOptions.none, when: FreezedWhenOptions.none)` on
  Result only (hand-written `map` disambiguation) — correct for freezed 3.2.5.

### (g) Tests — PASS
- 13/13 components have a 1:1 widget test file; every test's `_wrap` provides
  ProviderScope > MaterialApp(WavelyThemes.dark(purple)) > Scaffold(Center).
- themes_test.dart covers all 4 factory combos + `context.wavelyColors` +
  ThemeSettingsNotifier (defaults, 3 setters with persistence roundtrip, load).
- Golden file exists; shimmer exclusion documented in the file header;
  baselines not yet generated (owner runs `flutter test --update-goldens
  test/goldens` once per platform — see Known gaps #4).
- Test-symbol spot-checks vs implementation: track_tile `03:33` for 213000 ms ✓,
  mini_player `play_arrow_rounded`/`pause_rounded` ✓ (matches its own test),
  chip_filter decoration alphas 0.18/transparent ✓, progress_ring clamp ✓,
  semantics keys 'wavely.trackTile.semantics'/'wavely.chipFilter.semantics'/
  'wavely.explicitBadge.semantics'/'wavely.trackTile.selected' all match ✓.

---

## Known gaps

1. **ErrorState signature mismatch at ONE 3-c call site (REPORTED, not fixed —
   out of scope).** `lib/features/lyrics/presentation/lyrics_view.dart:91-95`
   calls `ErrorState(title: …, subtitle: …, onRetry: …)` but the Task 3-a
   contract is `ErrorState({required String message, String? detail, required
   VoidCallback onRetry})` → compile error (no `title`/`subtitle` params).
   Part-2 agent fix: rename `title:` → `message:` and `subtitle:` → `detail:`.
   All other 8 ErrorState call sites (search_screen, genres/folders/artists/
   albums/all_tracks tabs, album/artist detail screens) already use
   `message:`/`detail:` — consistent. 3-c's EmptyState assumption
   ({icon,title,subtitle}) is a strict subset of 3-a's
   ({icon,title,subtitle,ctaLabel,onCta}) — all EmptyState call sites compile.
2. **MiniPlayer icon assumption in 3-c test (REPORTED, not fixed — other
   agent's test).** `mini_player.dart` uses `Icons.play_arrow_rounded` /
   `Icons.pause_rounded`; `test/player/mini_player_host_test.dart:86` taps
   `find.byIcon(Icons.play_arrow)` (plain, different codepoint) → that test
   would fail. Part-2 agent fix: change the test to
   `Icons.play_arrow_rounded` (implementation is internally consistent and
   covered by test/design_system/components/mini_player_test.dart).
3. **Web build still blocked by dart:io in components (BY INSTRUCTION).**
   track_tile/mini_player/artist_circle/album_card use `Image.file(File(path))`
   per Task 3-a's explicit instruction (documented in the 3-a worklog:
   conditional-import wrapper required before web targets build). NOT changed
   here — fixing it is a Task 4/part-2 decision (the local_cover.dart
   conditional-import trio in features/library is the in-repo pattern to copy).
4. **Golden baselines do not exist yet** (no test/goldens/goldens/*.png). Owner
   must run `flutter test --update-goldens test/goldens` once per platform and
   commit. golden_toolkit 0.15.0 vs Flutter 3.35 view-API window also needs the
   owner's first compile (flagged by 3-a, still open).
5. **All .freezed.dart parts pending build_runner** (project-wide, expected —
   no SDK in sandbox).
6. **ThemeSettingsNotifier write-before-load race** (minor, by design): the
   constructor fires `_load(store)` async; a setter called before the load
   completes silently drops its persist (`_store` still null). Tests rely on
   InMemorySettingsStore resolving immediately. Not fixed (behavioral change
   out of audit scope; noted for Task 4 if a real async store makes it visible).
7. **GlassCard `onTap` uses InkWell, not a Semantics button wrapper** —
   accessibility label comes from content; acceptable, no a11y regression
   found (tap target is the whole card). No change.

---

## Fixes applied

| file | what changed |
|---|---|
| lib/core/utils/platform_utils.dart | **Rewritten** as a conditional-export barrel: `export 'package:wavely/core/utils/platform_utils_io.dart' if (dart.library.js_interop) 'package:wavely/core/utils/platform_utils_web.dart';`. Public import path and every public symbol unchanged — zero call-site changes. Reason: the file imported `dart:io` unconditionally; dart:io docs (Dart 3.9.4, api.dart.dev): "Browser-based apps can't use this library" → web-compiled consumers (lib/features/player/presentation/now_playing_screen.dart, lib/features/library/presentation/folders_tab.dart import it) would fail to build for web. Matches the repo's existing conditional-import convention (engine_factory, local_cover, library_scanner). |
| lib/core/utils/platform_utils_io.dart | NEW — exact former content of platform_utils.dart (PlatformUtils, DeviceInfoSnapshot, DeviceInfoProvider, isLowEndDevice, defaultDeviceInfoProvider with device_info_plus 13.x `physicalRamSize`/`version.sdkInt`/`Platform.numberOfProcessors`), plus arm doc header. |
| lib/core/utils/platform_utils_web.dart | NEW — web arm with the identical public surface, no dart:io: `isWeb` (kIsWeb), `isMobile`/`isDesktop` false, `currentTargetPlatform` = defaultTargetPlatform, same pure `isLowEndDevice`, `defaultDeviceInfoProvider()` → null (identical to the io arm's documented "unsupported platforms resolve to null"). KEEP IN SYNC notes in both arms. |

Re-verification after the fix: import-existence script re-run (ALL OK),
balanced-delimiter scan re-run (71 files, 0 problems), both new files re-read
top-to-bottom, test/core/platform_utils_test.dart still compiles against the
unchanged public surface (resolves to the io arm on the VM).

No other file in scope needed changes: no syntax/null-safety errors found, no
missing consts that any rule requires, no part-directive mismatches, no
touch-target regressions (all interactive elements ≥44dp verified by read +
matching tests), no test references to non-existent symbols in-scope.

---

## Left as TODO(verify)

Compiler-only items (no SDK here); each carries an exact expected signature:

1. `lib/features/lyrics/presentation/lyrics_view.dart:91` — part-2 must apply:
   `ErrorState({required String message, String? detail, required VoidCallback
   onRetry})` per lib/design_system/components/error_state.dart (Task 3-a).
2. `test/player/mini_player_host_test.dart:86` — part-2 must change
   `Icons.play_arrow` → `Icons.play_arrow_rounded` (mini_player.dart:104).
3. Generated parts must exist before any of this resolves: run build_runner
   (freezed 3.2.5) — failures.freezed.dart, result.freezed.dart,
   theme_provider.freezed.dart, 9 entity parts, + all 3-b/3-c parts.
4. golden_toolkit 0.15.0 `testGoldens`/`DeviceBuilder`/`pumpDeviceBuilder`/
   `screenMatchesGolden` signatures assumed per golden_toolkit 0.15.0 docs —
   confirm on first compile against Flutter 3.35.
5. freezed 3.2.5 emits `map`/`when` as extensions for the 11 other @freezed
   classes (re-added in 3.1.0) — no hand-written member collides in scope
   (only Result disables them, deliberately).

---

## Contract notes for Task 4

- **Component ctors (all const, import via
  `package:wavely/design_system/design_system.dart`)** — verified against
  source, not just the worklog:
  - `GlassCard({required Widget child, double? blurSigma, BorderRadius?
    borderRadius, EdgeInsetsGeometry? padding, Color? color, bool elevated =
    false, VoidCallback? onTap, Key? key})` — ConsumerWidget, needs
    ProviderScope; NEVER inside ListView items.
  - `TrackTile({required Track track, VoidCallback? onTap, VoidCallback?
    onLongPress, Widget? trailing, bool selected = false, bool
    showSourceBadge = false, Key? key})`; `WavelyCoverFallback({required
    String label, Key? key})` (fills parent; exported from track_tile.dart).
  - `ArtistCircle({required String name, String? coverPath, double radius =
    28, VoidCallback? onTap, Key? key})`.
  - `AlbumCard({required String title, required String artist, String?
    coverPath, VoidCallback? onTap, double width = 160, Key? key})`.
  - `MiniPlayer({required Track? track, required bool isPlaying, required
    Duration position, required Duration duration, required VoidCallback
    onPlayPause, required VoidCallback onTap, VoidCallback? onNext, Key? key})`.
  - `SectionHeader({required String title, String? actionLabel = 'See all',
    VoidCallback? onAction, Key? key})`.
  - `ChipFilter({required String label, required bool selected, required
    ValueChanged<bool> onSelected, IconData? icon, Key? key})`.
  - `Shimmer({required Widget child, Key? key})`; `ShimmerBox({double? width,
    double? height, BorderRadius? radius, Key? key})`.
  - `EmptyState({required IconData icon, required String title, String?
    subtitle, String? ctaLabel, VoidCallback? onCta, Key? key})`.
  - `ErrorState({required String message, String? detail, required VoidCallback
    onRetry, Key? key})` — note `message`/`detail`, NOT title/subtitle.
  - `ProgressRing({double? value, double size = 36, double strokeWidth = 3,
    Color? color, Key? key})`; `ExplicitBadge({double size = 16, Key? key})`;
    `SourceBadge({required String sourceId, double size = 14, bool
    withTooltip = true, Key? key})`.
- **Test hooks**: ValueKeys 'wavely.trackTile.selected',
  'wavely.trackTile.semantics', 'wavely.chipFilter.semantics',
  'wavely.explicitBadge.semantics' (MergeSemantics/Semantics nodes).
- **Settings/theme**: `settingsStoreProvider` and `themeSettingsProvider` both
  in lib/design_system/themes/theme_provider.dart (types in §d). Task 4's
  AppSettings (canonical settings, Task 4) should either re-export or wrap
  these; GlassCard only needs `themeSettingsProvider` to expose
  `ThemeSettings.reduceTransparency` — it is a plain ConsumerWidget
  `ref.watch(themeSettingsProvider).reduceTransparency` (glass_card.dart:45),
  trivially re-pointable or overridable at the root; no GlassCard change
  required for Task 4.
- **Accent mapping**: `WavelyAccent { purple, green }`;
  `WavelyAccentX.colors` → AccentColors{accent, hover, gradientStart}:
  purple = #7C5CFF / #9B7BFF / #5B3FD9; green = #1DB954 / #1ED760 / #0FA34A.
  `WavelyThemes.light/dark(WavelyAccent)` register WavelySemanticColors — any
  custom ThemeData MUST copy `extensions:` or `context.wavelyColors` throws.
- **PlatformUtils**: import path/symbols unchanged after this audit's
  conditional-export split (io/web arms in platform_utils_io/web.dart).
  `PlatformUtils.isDesktop` (used by 3-c's io engine arm and 3-b's scanner)
  is native-only; on web both isMobile/isDesktop are false.
- **Do not "fix"** int-literal doubles (`static const double xs = 4;`) —
  prefer_int_literals requires them; do not swap AppBarThemeData/
  CardThemeData/InputDecorationThemeData back to the old names.

## Part 2 — Data, features, playback, lyrics (Task 3-b + 3-c scope)

# Stage 1.1 — Audit Part 2 (data / features / playback / tests)

Task ID: A2 (part 2 of 2). Auditor: general-purpose subagent. No Flutter/Dart SDK
in the sandbox — everything below is BY INSPECTION plus pub.dev doc verification
(see "Left as TODO(verify)" for the exact citations). Scope: `lib/data/**`,
`lib/domain/usecases/**`, `lib/features/{library,search,lyrics,player}/**`,
`lib/playback/**` (except the abstract engine contract), `lib/core/utils/
stable_hash.dart`, and `test/{db,scanner,library,search,playback,lyrics,player}`.
Nothing was compiled; verification is structural + API-doc cross-checks.

---

## Inventory (path | lines | purpose | status)

### Data layer
| Path | Lines | Purpose | Status |
|---|---|---|---|
| lib/data/local/db/tables/tracks.dart | 54 | Primary library table; unique (sourceId,sourceTrackId) + title/artist indexes | PASS |
| lib/data/local/db/tables/albums.dart | 26 | Album projection (unique key `artist::title` lowercased) | PASS |
| lib/data/local/db/tables/artists.dart | 20 | Artist projection (unique name) | PASS |
| lib/data/local/db/tables/playlists.dart | 17 | User playlists | PASS |
| lib/data/local/db/tables/playlist_items.dart | 36 | Ordered membership; unique (playlistId,trackId); cascades | PASS |
| lib/data/local/db/tables/liked_tracks.dart | 17 | Likes; unique trackId | PASS |
| lib/data/local/db/tables/plays.dart | 30 | Listening sessions; trackId/startedAt indexes | PASS |
| lib/data/local/db/tables/lyrics_cache.dart | 35 | Lyrics per (track,provider), unique index, offsetMs | PASS |
| lib/data/local/db/app_database.dart | 75 | @DriftDatabase 8 tables + 3 DAOs, schemaVersion 1, FTS create/drop | PASS |
| lib/data/local/db/migrations/0001_init.dart | 65 | FTS5 virtual table + 3 trigger SQL constants | PASS |
| lib/data/local/db/daos/tracks_dao.dart | 394 | CRUD, upsert-by-source, paging, FTS search, projections | PASS |
| lib/data/local/db/daos/plays_dao.dart | 72 | Play history + playCount/lastPlayedAt stats | PASS |
| lib/data/local/db/daos/lyrics_dao.dart | 76 | Lyrics cache get/upsert (ON CONFLICT)/updateOffset | PASS |
| lib/data/local/db/database_provider.dart | 11 | databaseProvider + ref.onDispose close | PASS |
| lib/data/local/db/mappers/track_mapper.dart | 58 | TracksRow ↔ Track, companion builder (nulls clear columns) | PASS |
| lib/data/repositories/drift_lyrics_cache.dart | 52 | LyricsCache port over LyricsDao | PASS |
| lib/data/repositories/drift_queue_track_source.dart | 29 | QueueTrackSource honoring persisted id order | PASS |
| lib/data/repositories/queue_track_launcher.dart | 22 | TrackLauncher → QueueManager adapter (setQueue+play) | PASS |
| lib/data/repositories/shared_prefs_settings_store.dart | 57 | SettingsStore over SharedPreferences (type-switch read) | PASS |

### Domain usecases + utils
| Path | Lines | Purpose | Status |
|---|---|---|---|
| lib/domain/usecases/scan_library.dart | 472 | Batched Isolate.run metadata scan; persists tracks/lyrics/covers/projections | PASS (IO-only by design; now only reachable via IO arm) |
| lib/domain/usecases/search_local.dart | 101 | FTS + client-side artist/album grouping | PASS |
| lib/core/utils/stable_hash.dart | 37 | FNV-1a 64 → base36; hashList with \x1f separator | PASS |

### Features
| Path | Lines | Purpose | Status |
|---|---|---|---|
| lib/features/library/data/library_scanner.dart | 63 | Abstract facade + ScanFoldersStore (web-safe, no dart:io) | FIXED (split, see Fixes #5) |
| lib/features/library/data/library_scanner_provider.dart | 13 | Conditional-export hub for the scanner binding | NEW |
| lib/features/library/data/library_scanner_provider_io.dart | 32 | IO arm: ScanLibrary + Desktop/Mobile selection | NEW |
| lib/features/library/data/library_scanner_provider_web.dart | 14 | Web arm: disabled web scanner | NEW |
| lib/features/library/data/library_scanner_android.dart | 80 | Mobile scanner + SAF persist stub (MethodChannel) | PASS |
| lib/features/library/data/library_scanner_desktop.dart | 141 | Desktop scanner + polling watcher (file_system has no Watcher) | PASS |
| lib/features/library/data/library_scanner_web.dart | 29 | Web stub: scan completes with explanatory error | PASS |
| lib/features/library/data/track_launcher.dart | 25 | TrackLauncher port + throwing provider (Task 4 overrides) | FIXED (=0 default added) |
| lib/features/library/presentation/library_providers.dart | 260 | Paged/grouped providers + ScanStateNotifier | PASS (import updated) |
| lib/features/library/presentation/library_screen.dart | 90 | 5-tab shell, route '/library' | PASS |
| lib/features/library/presentation/folders_tab.dart | 178 | Folder mgmt + scan progress | PASS (import updated) |
| lib/features/library/presentation/artists_tab.dart | 101 | Artist grid | PASS |
| lib/features/library/presentation/albums_tab.dart | 82 | Album grid | PASS |
| lib/features/library/presentation/genres_tab.dart | 149 | Genre chips + filtered list | PASS |
| lib/features/library/presentation/all_tracks_tab.dart | 154 | Infinite paged list (200/page) | PASS |
| lib/features/library/presentation/artist_detail_screen.dart | 148 | '/library/artist' + '/:name' pattern | PASS |
| lib/features/library/presentation/album_detail_screen.dart | 167 | '/library/album' + '/:artist/:album' pattern | PASS |
| lib/features/library/presentation/local_cover.dart | 1 | Conditional export hub `stub if (dart.library.io) io` | PASS (pattern correct) |
| lib/features/library/presentation/local_cover_io.dart | 16 | FileImage provider (existsSync guard) | PASS |
| lib/features/library/presentation/local_cover_stub.dart | 5 | Web: always null | PASS |
| lib/features/search/presentation/search_providers.dart | 111 | Debounce controller (300ms) + state | PASS |
| lib/features/search/presentation/search_screen.dart | 281 | Grouped results UI, route '/search' | PASS |
| lib/features/lyrics/data/lyrics_cache.dart | 80 | LyricsCache port + NullLyricsCache + provider | FIXED (dead branch removed) |
| lib/features/lyrics/data/embedded_lyrics_provider.dart | 41 | Cache-only 'embedded' provider | PASS |
| lib/features/lyrics/data/lrclib_lyrics_provider.dart | 144 | lrclib.net get→search fallback, never throws | PASS |
| lib/features/lyrics/data/lyrics_repository.dart | 114 | Cache-first chain; winner cached | FIXED (provider failures guarded) |
| lib/features/lyrics/domain/lrc_parser.dart | 182 | Pure LRC/enhanced-LRC parser | PASS |
| lib/features/lyrics/domain/lyrics_sync_controller.dart | 62 | position→active-line index stream | PASS |
| lib/features/lyrics/presentation/lyrics_view.dart | 393 | Synced/plain renderer + offset sheet | FIXED (ErrorState args) |
| lib/features/player/presentation/now_playing_screen.dart | 447 | Now playing; route '/now-playing' | FIXED (dart:io removed) |
| lib/features/player/presentation/queue_sheet.dart | 139 | Reorder + dismiss sheet content | PASS |
| lib/features/player/presentation/mini_player_host.dart | 52 | Collapse/slide-in host | PASS |

### Playback
| Path | Lines | Purpose | Status |
|---|---|---|---|
| lib/playback/engines/playback_engine.dart | 29 | ABSTRACT CONTRACT — out of scope, untouched | UNTOUCHED |
| lib/playback/engines/engine_factory.dart | 17 | playbackEngineProvider + conditional engine selection | PASS |
| lib/playback/engines/playback_engine_io.dart | 15 | IO arm (media_kit desktop / just_audio mobile) | PASS |
| lib/playback/engines/playback_engine_web.dart | 6 | Web arm | PASS |
| lib/playback/engines/playback_engine_stub.dart | 6 | Fallback arm | PASS |
| lib/playback/engines/mobile_playback_engine.dart | 265 | just_audio + audio_service handler + audio_session | PASS |
| lib/playback/engines/desktop_playback_engine.dart | 162 | media_kit (player.stream singular; dedup, no completed-downgrade) | PASS |
| lib/playback/engines/web_playback_engine.dart | 209 | dart:js_interop HTMLAudioElement | PASS (web-only; see smoke-test fix) |
| lib/playback/queue/queue_manager.dart | 588 | QueueState freezed + QueueManager + providers | PASS |
| lib/playback/shuffle/basic_shuffle.dart | 84 | Deterministic Fisher-Yates + no-repeat window | PASS |

### Tests
| Path | Lines | Purpose | Status |
|---|---|---|---|
| test/db/app_database_test.dart | 192 | Tracks roundtrip/upsert/paging/byIds/counts | PASS |
| test/db/fts_test.dart | 127 | searchFts + trigger propagation (update/delete) | PASS |
| test/db/plays_dao_test.dart | 135 | plays CRUD, totals, topTracks, stats | PASS |
| test/db/lyrics_dao_test.dart | 116 | upsert/get-best-row/offset | PASS |
| test/scanner/scan_library_test.dart | 195 | 5 flows against test/fixtures/audio (10 files EXIST, verified by ls) | PASS |
| test/library/folders_tab_test.dart | 123 | Mocked scanner/store widget tests | PASS (import updated) |
| test/library/all_tracks_tab_test.dart | 114 | Memory db + fake launcher | PASS |
| test/search/search_local_test.dart | 108 | Usecase grouping | PASS |
| test/search/search_screen_test.dart | 103 | Debounce + empty states | PASS |
| test/playback/basic_shuffle_test.dart | 127 | 10 cases incl. seed 0 / infeasible window | PASS |
| test/playback/queue_manager_test.dart | 517 | 23 cases | PASS |
| test/playback/engine_contract_test.dart | 115 | Contract suite vs FakePlaybackEngine | PASS |
| test/playback/engine_contract_smoke_test.dart | 37 | Hub; conditional platform arms | FIXED (see Fixes #6) |
| test/playback/engine_contract_smoke_arms.dart | 28 | VM/default arm (mobile+desktop, skipped) | NEW |
| test/playback/engine_contract_smoke_arms_web.dart | 34 | Web arm (+ HTMLAudioElement, skipped) | NEW |
| test/playback/fake_playback_engine.dart | 84 | Hand-rolled fake | PASS |
| test/lyrics/lrc_parser_test.dart | 155 | 18 cases (≥10 required) | PASS |
| test/lyrics/lyrics_sync_controller_test.dart | 141 | 6 cases | PASS |
| test/lyrics/lrclib_provider_test.dart | 198 | mocktail Dio; 404→search, timeouts, no-id | PASS |
| test/lyrics/lyrics_repository_test.dart | 156 | Chain + cache semantics | PASS (was failing → impl fixed) |
| test/lyrics/fakes.dart | 118 | Recording fakes | PASS |
| test/player/now_playing_screen_test.dart | 122 | 7 cases | PASS |
| test/player/queue_sheet_test.dart | 133 | 5 cases | PASS |
| test/player/mini_player_host_test.dart | 106 | 4 cases | FIXED (icon glyph) |

---

## Consistency findings (a–i)

**a. Import-path existence — PASS.** Scripted check over every
`package:wavely/...` import in lib+test: all resolve. Relative imports exist
ONLY inside test/ for shared test helpers (`fake_playback_engine.dart`,
`fakes.dart`, `engine_contract_test.dart`, `../playback/...`) — idiomatic for
test trees, not a violation. No relative imports in lib/.

**b. DAO ↔ table match — PASS.** Every column referenced by every DAO method
exists in the corresponding Table class (checked column-by-column, including
`genre`/`language` on Tracks, `offsetMs`/`fetchedAt` on LyricsCache).
`customSelect` placeholder/variable counts match: tracksDao.getAll 2/2,
searchFts 2/2, topTracks 1/1, upsertArtistProjection 1/1 + 1/1,
lyricsDao.upsert 5/5, playsDao.incrementTrackPlayStats 2/2. part directives
correct: `tracks_dao.g.dart`→`_$TracksDaoMixin`, `plays_dao.g.dart`,
`lyrics_dao.g.dart`, `app_database.g.dart`→`_$AppDatabase`;
`queue_manager.freezed.dart` for the freezed class. `references(Tracks, #id,
onDelete: …)` and `@TableIndex(columns: {#sym})` match drift 2.35.3 API.
`Expression.collate` — drift exposes it via the `StringExpressionOperators`
extension; `Collate.noCase` is the correct constant name (verified in drift
2.35.3 docs; note it is `noCase`, not SQLite's `NOCASE`).

**c. FTS5 — PASS.** External-content table
`fts5(title, artist, album, content='tracks', content_rowid='id')`; insert
trigger `INSERT INTO tracks_fts(rowid, …) VALUES (new.id, …)`; delete trigger
uses the `'delete'` command row `INSERT INTO tracks_fts(tracks_fts, rowid, …)
VALUES ('delete', old.id, …)`; update trigger does delete-old-then-insert-new
— exactly the SQLite FTS5 external-content recipe. searchFts builds
`"tok1" "tok2"*` (each token double-quoted, internal quotes doubled, only the
LAST token gets `*`), MATCH via bind variable, joins on `t.id = f.rowid`,
orders by `f.rank`, capped at AppConstants.ftsPageSize. fts_test covers
partial-word, multi-token AND, update/delete propagation.

**d. Cross-task contract mismatches — 2 FAILs, both fixed at call sites:**
- FAIL→FIXED: `lyrics_view.dart` error branch used
  `ErrorState(title:, subtitle:)` but 3-a's real signature is
  `ErrorState({required String message, String? detail, required VoidCallback
  onRetry})` → renamed to message/detail. All other 8 ErrorState call sites
  (library/search) already used message/detail; all EmptyState call sites
  match `EmptyState({required IconData icon, required String title, String?
  subtitle, String? ctaLabel, VoidCallback? onCta})`.
- FAIL→FIXED: `mini_player_host_test.dart` found
  `Icons.play_arrow`; 3-a's MiniPlayer renders `Icons.play_arrow_rounded`
  (idle) / `Icons.pause_rounded` (playing) → test finder + NOTE comment
  aligned to 3-a.
- Verified matching: `MiniPlayerHost({required VoidCallback onOpenNowPlaying})`
  ✓, `QueueSheet({required VoidCallback? onClose})` ✓ (test passes
  `onClose: null` — legal for nullable required), `NowPlayingScreen()` const +
  `static const route '/now-playing'` ✓. `settingsStoreProvider` exists in
  `design_system/themes/theme_provider.dart` typed `Provider<SettingsStore>`
  ✓ (re-exported by the design_system barrel; library/player tests import it
  from the barrel). `lyricsCacheProvider` lives in
  `features/lyrics/data/lyrics_cache.dart` and is consumed by
  lyrics_view.dart + lyrics_repository.dart, overridden by DriftLyricsCache in
  lib/app/providers.dart ✓.

**e. Section 5 contract conformance — PASS.** All three engine impls
implement the full abstract set (load/play/pause/seek/positionStream/
stateStream/setQueue/dispose) — verified member-by-member. SourceProvider and
LyricsProvider contract files untouched. LrcParser produces
`LyricWord(start, end?, text)` / `LyricLine(startTime, endTime?, text,
words?)` / `LyricsResult(lines, metadata, synced)` — exact shapes of
domain/entities/lyrics_entities.dart.

**f. Riverpod mix — PASS (100% manual providers).** No `@riverpod`/
`riverpod_annotation` anywhere in scope — no codegen mix to reconcile.
Inventory: manual `Provider`: databaseProvider(AppDatabase), settingsStoreProvider
(3-a, upstream), libraryScannerProvider (conditional hub), trackLauncherProvider
(throws by design), searchLocalProvider, lyricsCacheProvider,
lyricsRepositoryProvider, playbackEngineProvider, queueTrackSourceProvider.
`FutureProvider`: tracksPaged.family<int>, artistTracks.family<String>,
albumTracks.family<({String artist,String album})>, genreTracks.family<String>,
artists, albums, genres, libraryCount, folders; lyricsFuture.family<Track>,
lyricsOffset.family<int>. `StateNotifierProvider`: scanStateProvider,
searchResultsControllerProvider, queueManagerProvider (upstream 3-a:
themeSettingsProvider). No mass refactor needed or performed.

**g. Hard-coded values — PASS.** Grep for `Color(0x`, `BorderRadius.circular`,
`TextStyle(`, `Duration(milliseconds:` across scope: zero raw colors/radii/
text styles; every `Duration(milliseconds:)` is ms arithmetic
(positions/durations) or an AppConstants-backed const (`searchDebounceMs`).
Private numeric consts all carry doc comments (e.g. `_shimmerRowHeight`,
`_playButtonSize`, `_batchSize`, `_timeout`). Whole-double tokens are written
as int literals per the VGA-11 prefer_int_literals convention.

**h. Test coverage — PASS (with 2 gaps noted, see Known gaps).** All DAOs have
tests (tracks/fts/plays/lyrics, all NativeDatabase.memory()). Scanner test hits
`test/fixtures/audio` — all 10 fixture files exist (verified by ls; plus
`11_unsupported.txt` which the test asserts is skipped). search_local +
search_screen, basic_shuffle/queue_manager/engine_contract/smoke(skip)/fake,
lrc_parser (18 cases ≥10)/sync_controller/lrclib_provider/lyrics_repository,
now_playing/queue_sheet/mini_player_host — every required suite present; no
whole suite had to be authored. Test-vs-impl mismatch found: lyrics repository
"provider failure resilience" test would FAIL because `LyricsRepository.fetch`
did not guard `provider.fetch` — fixed the IMPLEMENTATION (the worklog 3-c
contract explicitly lists provider-failure resilience).

**i. dart:io in shared files (web build) — 2 FAILs, both fixed:**
- `now_playing_screen.dart` imported dart:io and used `Image.file(File(...))`
  → web compile break. Now uses the existing `local_cover` conditional-import
  helper (`localCoverProvider`) via `Image(image: provider, errorBuilder:)`;
  web/missing-file case falls back to the gradient/icon exactly as before.
- `library_scanner.dart` (shared facade) imported `scan_library.dart`
  (dart:io+isolate) and `library_scanner_android/desktop.dart` inside the
  unconditional `libraryScannerProvider` → any web file importing the facade
  failed to compile. Split into `library_scanner_provider.dart`
  (`export web if (dart.library.io) io`) + IO/Web arms; facade now holds only
  the abstract class + ScanFoldersStore and is dart:io-free.
- Verified correct: `local_cover.dart` (`export 'local_cover_stub.dart' if
  (dart.library.io) 'local_cover_io.dart'` — default-first order is correct),
  playback engine factory arms (`stub | js_interop | io`).
- design_system (REPORT ONLY, not edited): `track_tile.dart` uses dart:io
  `Image.file` directly per Task 3-a's own note → breaks `flutter build web`;
  same for `lib/domain/repositories/source_provider.dart` (dart:io File in the
  interface, Task 2 file, documented in its doc comment). Both belong to
  A1/orchestrator.

---

## Known gaps

1. No direct tests read the `albums`/`artists` PROJECTION TABLES: the scanner
   test asserts `distinctArtists()`/`distinctAlbums()`, but those query
   `tracks` (not the projections), so `upsertAlbumProjection`/
   `upsertArtistProjection` are exercised only for "does not throw". Not a
   missing suite (DAO tests exist) — a candidate micro-test for Task 4/5.
2. `TracksDao.byArtist/byAlbum/byGenre/distinctGenres` have no dedicated DAO
   tests (byArtist/byAlbum indirectly covered by scanner + detail-screen data
   paths; byGenre/distinctGenres uncovered). Suggested small addition.
3. design_system `track_tile.dart` + domain `source_provider.dart` still break
   web compile (dart:io) — OUT of A2 scope, reported for A1/orchestrator.
4. `CachedLyrics.toResult()` is a documented always-null placeholder kept for
   API stability (parsing lives in LrcParser/repository); harmless but could
   be deleted in a later cleanup if nothing references it by Task 4 review.
5. Golden baselines for components do not exist yet (3-a note; owner must run
   `flutter test --update-goldens test/goldens` once per platform).
6. All freezed/drift `part` files (entities, queue_manager.freezed.dart,
   *.g.dart) are pending the owner's `dart run build_runner build`.

---

## Fixes applied (file → change)

1. `lib/features/lyrics/presentation/lyrics_view.dart` → ErrorState call site
   renamed `title:`→`message:`, `subtitle:`→`detail:` to match the real 3-a
   signature (was a guaranteed compile error).
2. `lib/features/lyrics/data/lyrics_repository.dart` → `fetch` now wraps
   `provider.fetch(t)` in try/catch (`on Object catch (_) { continue; }`) so a
   failing provider degrades to the next one — restores the worklog 3-c
   "provider failure resilience" contract; makes
   `test/lyrics/lyrics_repository_test.dart` ('provider failures do not break
   the chain') pass.
3. `lib/features/lyrics/data/lyrics_cache.dart` → removed the dead branch in
   `CachedLyrics.toResult()` (both paths returned null); single documented
   `=> null` body.
4. `test/player/mini_player_host_test.dart` → play/pause finder
   `Icons.play_arrow` → `Icons.play_arrow_rounded` + NOTE comment updated to
   state 3-a's actual glyphs (play_arrow_rounded / pause_rounded).
5. `lib/features/player/presentation/now_playing_screen.dart` → removed
   `dart:io`; backdrop + cover now render through `localCoverProvider` (the
   library feature's conditional-import helper) with the previous
   fallback/errorBuilder behavior preserved (`Image(image:, fit:, errorBuilder:)`).
6. Scanner web-compile split:
   - `lib/features/library/data/library_scanner.dart` → slimmed to abstract
     `LibraryScanner` + `ScanFoldersStore` only (no dart:io, no riverpod).
   - NEW `library_scanner_provider.dart` → conditional export hub
     (`export 'library_scanner_provider_web.dart' if (dart.library.io)
     'library_scanner_provider_io.dart';`).
   - NEW `library_scanner_provider_io.dart` → old provider body (ScanLibrary
     + Desktop/Mobile selection by PlatformUtils.isDesktop).
   - NEW `library_scanner_provider_web.dart` → binds `WebLibraryScanner`.
   - `library_providers.dart`, `folders_tab.dart`, `test/library/
     folders_tab_test.dart` → added the hub import (facade import kept for
     `LibraryScanner`/`ScanFoldersStore`).
7. `lib/features/library/data/track_launcher.dart` → the abstract member
   declared `Future<void> playTracks(List<Track> tracks, {int startIndex})` —
   a non-nullable named parameter with NO default and NO `required`, which is
   a null-safety compile error ("the implicit default value is 'null'").
   Fixed to `{int startIndex = 0}`, matching both existing implementations
   (`QueueTrackLauncher`, test fake) and every call site.
8. `test/playback/engine_contract_smoke_test.dart` → rewritten as a hub whose
   arm file is conditionally imported (`if (dart.library.js_interop) …`);
   NEW `engine_contract_smoke_arms.dart` (VM/default arm: mobile+desktop
   suites, skipped) and `engine_contract_smoke_arms_web.dart` (web arm: adds
   the HTMLAudioElement suite). Reason: `dart:js_interop` does not exist on
   the VM target (verified against the Dart SDK `sdk/lib/libraries.json`: the
   `vm` target has no `js_interop` entry), so the previous unconditional
   import of `web_playback_engine.dart` would fail to COMPILE under plain
   `flutter test` — `skip:` does not prevent compilation.

---

## Left as TODO(verify)

Nothing in scope required an unverifiable API guess — every uncertain API was
confirmed against docs, so there are NO `// TODO(verify):` markers to report.
Doc citations used during the audit (all verified live):

- drift 2.35.3 — `StringExpressionOperators.collate` +
  `Collate.noCase`/`binary`/`rTrim`:
  https://pub.dev/documentation/drift/2.35.3/drift/StringExpressionOperators/collate.html
  and https://pub.dev/documentation/drift/2.35.3/drift/Collate-class.html
- drift 2.35.3 — `OrderingTerm.asc/desc`:
  https://pub.dev/documentation/drift/2.35.3/drift/OrderingTerm/OrderingTerm.asc.html
- drift_flutter — `driftDatabase(name:)`:
  https://pub.dev/documentation/drift_flutter/latest/drift_flutter/driftDatabase.html
- audio_metadata_reader 1.8.1 — `AudioMetadata` fields (title/artist/album/
  genres/language/lyrics/bitrate/duration/pictures all exist):
  https://pub.dev/documentation/audio_metadata_reader/1.8.1/audio_metadata_reader/AudioMetadata-class.html
- audio_metadata_reader 1.8.1 — `readMetadata(File, {getImage})` and
  `NoMetadataParserException`:
  https://pub.dev/documentation/audio_metadata_reader/1.8.1/audio_metadata_reader/readMetadata.html
  , https://pub.dev/documentation/audio_metadata_reader/1.8.1/audio_metadata_reader/NoMetadataParserException-class.html
- file_picker 13.3.0 — `FilePicker.getDirectoryPath`:
  https://pub.dev/documentation/file_picker/13.3.0/file_picker/FilePicker/getDirectoryPath.html
- lrclib — response shape `{id, trackName, artistName, albumName, duration,
  instrumental, plainLyrics, syncedLyrics}` per live API check recorded by
  Task 3-c (provider code matches field-for-field).
- Dart SDK `sdk/lib/libraries.json` (github.com/dart-lang/sdk): the `vm`
  target contains no `js_interop` library → dart:js_interop is web-only
  (basis for fix #6 and for keeping web_playback_engine out of VM-compiled
  files).

Pre-existing follow-ups (owned elsewhere, unchanged by A2): build_runner pass
for all `part` files; golden baselines; MiniPlayer/EmptyState/ErrorState now
all verified consistent so 3-c's "known follow-ups" item about signatures is
CLOSED by this audit.

---

## Contract notes for Task 4 (exact signatures)

- **ScanLibrary** (`lib/domain/usecases/scan_library.dart`):
  `ScanLibrary({required TracksDao tracksDao, required LyricsDao lyricsDao})`;
  `Stream<ScanEvent> scan({required List<String> folders, String? coversDir})`
  — broadcast stream, ends with `ScanEvent.completed(count:, errors:)`;
  events: `ScanStarted(root:)`, `TrackFound(track:)`,
  `ScanProgress(processed:, total:, currentFile:)`,
  `ScanError(file:, reason:)`. IO-only (dart:io + Isolate.run).
- **LibraryScanner** (`lib/features/library/data/library_scanner.dart`):
  `const LibraryScanner()` abstract — `Stream<ScanEvent> scan(List<String>
  folders)`, `Future<List<String>> pickFolders()`,
  `Future<List<String>> watchFolders()`. Impl classes:
  `MobileLibraryScanner({required ScanLibrary scanLibrary, required
  SettingsStore settingsStore})` in library_scanner_android.dart;
  `DesktopLibraryScanner({required ScanLibrary scanLibrary, required
  SettingsStore settingsStore, Future<String?> Function() coversDirResolver =
  defaultCoversDirResolver})` (+ extra `Stream<String> watch(String folder)`)
  in library_scanner_desktop.dart; `const WebLibraryScanner()` in
  library_scanner_web.dart. **Provider names after the A2 split**:
  `libraryScannerProvider` is exported from
  `features/library/data/library_scanner_provider.dart` (conditional hub; do
  NOT import it from `library_scanner.dart`). `ScanFoldersStore(store)`
  (`.read()/.write()`) stays in library_scanner.dart; folders persist under
  `AppConstants.settingsKeyPrefix + 'scanFolders'` (JSON list).
- **SearchLocal** (`lib/domain/usecases/search_local.dart`):
  `SearchLocal(this._tracksDao)` — positional TracksDao; `Future<SearchResults>
  call(String query)`; `SearchResults({tracks, artists, albums})` with
  `.isEmpty`. Bound by `searchLocalProvider` (search_providers.dart) watching
  databaseProvider.
- **LrcParser** (`lib/features/lyrics/domain/lrc_parser.dart`): static
  `LyricsResult parse(String raw)`; never throws; offset semantics
  effective = stamp − offset (positive → earlier), clamped at 0.
- **LyricsSyncController** (`features/lyrics/domain/lyrics_sync_controller.dart`):
  `LyricsSyncController({required List<LyricLine> lines, required
  Stream<Duration> positionStream})`; `Stream<int> get activeLineStream`
  (−1 before first line), `int get activeIndex`,
  `Duration? get nextTransition`, `void dispose()`.
- **LyricsRepository** (`features/lyrics/data/lyrics_repository.dart`):
  `LyricsRepository({required List<LyricsProvider> providers, required
  LyricsCache cache})`; `Future<LyricsResult?> fetch(Track t)` — cache-first,
  chain in order, first non-null with non-empty lines wins, provider
  exceptions degrade to the next provider (A2 fix), misses not cached.
- **lyricsRepositoryProvider** (same file): `Provider<LyricsRepository>`
  wiring embedded → lrclib (`Dio(BaseOptions(baseUrl:
  LrclibLyricsProvider.baseUrl))`), cache = `lyricsCacheProvider`. No override
  needed in the composition root; only `lyricsCacheProvider` gets overridden
  (already done in lib/app/providers.dart with DriftLyricsCache).
- **QueueManager** (`lib/playback/queue/queue_manager.dart`):
  `QueueManager({required PlaybackEngine engine, required SettingsStore store,
  QueueTrackSource? trackSource})` — StateNotifier<QueueState>. Methods:
  `Future<void> setQueue(List<Track>, {int startIndex = 0})`, `Future<void>
  play()`, `Future<void> pause()`, `Future<void> togglePlayPause()`,
  `Future<void> next()`, `Future<void> previous()`, `Future<void>
  toggleShuffle()`, `void setRepeatMode(RepeatMode)`, `void setSpeed(double)`
  (state-only until engines gain a rate API), `Future<void> seek(Duration)`,
  `Future<void> reorderQueue(int oldIndex, int newIndex)`, `Future<void>
  removeFromQueue(int index)`, `void startSleepTimer(Duration)`, `void
  cancelSleepTimer()`, `Future<void> restore()` (never auto-plays; no-op
  without a track source).
- **QueueState** fields: `List<Track> tracks`, `int currentIndex`,
  `RepeatMode repeatMode`, `bool shuffleEnabled`, `PlaybackState
  playbackState`, `Duration position`, `Duration duration`, `double speed`,
  `DateTime? sleepTimerEndsAt` + getters `hasCurrent`, `currentTrack`.
  Providers: `queueManagerProvider`,
  `queueTrackSourceProvider` (default resolves ids → []; Task 4 override =
  DriftQueueTrackSource, already present in lib/app/providers.dart).
  **QueueManager.play-recording hook: to be added by Task 4, NOT in A2.**
- **playbackEngineProvider** location:
  `lib/playback/engines/engine_factory.dart`
  (`Provider<PlaybackEngine>`; `ref.onDispose(engine.dispose)`).
  Factory conditional-import structure: engine_factory.dart imports
  `playback_engine_stub.dart if (dart.library.js_interop)
  playback_engine_web.dart if (dart.library.io) playback_engine_io.dart`;
  the IO arm picks `DesktopPlaybackEngine` when `PlatformUtils.isDesktop`
  else `MobilePlaybackEngine`. AudioService.init bootstrap snippet is in the
  MobilePlaybackEngine class doc (audioHandler getter).
- **Route constants from library screens**: `LibraryScreen.libraryRoute =
  '/library'`; `ArtistDetailScreen.artistRoute = '/library/artist'` (+
  `artistRoutePattern = '/library/artist/:name'`, ctor
  `ArtistDetailScreen({required String artistName})`);
  `AlbumDetailScreen.albumRoute = '/library/album'` (+ `albumRoutePattern =
  '/library/album/:artist/:album'`, ctor `AlbumDetailScreen({required String
  albumTitle, required String artistName})`); `SearchScreen.route = '/search'`;
  `NowPlayingScreen.route = '/now-playing'`.
- **trackLauncherProvider** (`lib/features/library/data/track_launcher.dart`):
  abstract `TrackLauncher` with `Future<void> playTracks(List<Track> tracks,
  {int startIndex = 0})` (A2 added the `= 0` default — the previous
  default-less non-nullable named param did not compile). Provider default
  throws `UnimplementedError` until overridden (already overridden by
  `QueueTrackLauncher` in lib/app/providers.dart — const ctor takes the
  manager positionally; `playTracks` = `setQueue` + `play`).
- Composition root reference: `lib/app/providers.dart::buildOverrides({required
  AppDatabase db, required SharedPreferences prefs})` returns the full
  override list (database/settingsStore/lyricsCache/queueTrackSource/
  trackLauncher).
