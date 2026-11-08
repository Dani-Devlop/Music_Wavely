/// Stage 6 — real-UI screenshot harness (the ARTEMIS screenshot
/// equivalent, produced on CI where the Android emulator cannot run).
///
/// Every capture pumps the REAL Wavely app (or, for the AI chat, the REAL
/// [AiChatScreen], which the router auth-guards in test builds) with the
/// same hermetic fakes the rest of the suite uses, drives it through the
/// user flow, and renders the live widget tree to a PNG.
///
/// Capture mode is compile-time gated so the regular test runs stay pure
/// assertions (no golden baselines to rot across Flutter upgrades):
///
///     flutter test test/goldens \
///       --dart-define=WAVELY_CAPTURE=true \
///       --dart-define=WAVELY_SCREENSHOT_DIR=docs/assets
///
/// Produces: home.png, now_playing.png, synced_lyrics.png, ai_chat.png,
/// settings.png (phone-shaped 720×1280 @2x).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/providers.dart';
import 'package:wavely/app/router.dart';
import 'package:wavely/app/wavely_app.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/sync/sync_providers.dart';
import 'package:wavely/data/sync/sync_service.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/ai_chat_providers.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/home/presentation/home_screen.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/data/track_launcher.dart'
    show trackLauncherProvider;
import 'package:wavely/features/onboarding/data/onboarding_state.dart';
import 'package:wavely/l10n/app_localizations.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import '../features/library/fakes.dart' show FakeLibraryScanner;
import '../support/ai_chat_fakes.dart';
import '../support/fake_playback_engine.dart';

/// Scanner fake that seeds the SAME database the app runs on (mirrors the
/// `ScanLibrary` usecase) and replays a started/completed event pair —
/// the same approach the e2e scan test uses, which drives the app's real
/// scan→invalidate→library-refresh path.
class _SeedingScanner extends FakeLibraryScanner {
  _SeedingScanner({
    required this.db,
    required this.tracks,
    required String pickedRoot,
  }) : super(
          picked: <String>[pickedRoot],
          events: <ScanEvent>[
            ScanEvent.scanStarted(root: pickedRoot),
            ScanEvent.completed(
              count: tracks.length,
              errors: const <String>[],
            ),
          ],
        );

  final AppDatabase db;
  final List<TracksCompanion> tracks;

  @override
  Stream<ScanEvent> scan(List<String> folders) async* {
    scanCalls++;
    scannedFolders.add(List<String>.of(folders));
    for (final track in tracks) {
      await db.tracksDao.insertTrack(track);
    }
    yield* Stream<ScanEvent>.fromIterable(events);
  }
}

/// Compile-time switches (see the file header).
const bool _kCapture =
    bool.fromEnvironment('WAVELY_CAPTURE');
const String _kDir = String.fromEnvironment(
  'WAVELY_SCREENSHOT_DIR',
  defaultValue: 'docs/assets',
);

const Key _kBoundaryKey = ValueKey('screenshot-boundary');

/// Everything a capture test needs to drive or assert against the pumped
/// app (a record — the shared harness class keeps a private constructor).
typedef _Harness = ({
  AppDatabase db,
  FakePlaybackEngine engine,
  ProviderContainer container,
});

/// Renders the current frame under the keyed repaint boundary to
/// `<_kDir>/<name>` at 2× pixel ratio. No-op outside capture mode.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!_kCapture) {
    return;
  }
  await tester.binding.runAsync(() async {
    final RenderRepaintBoundary boundary = tester.renderObject(
      find.byKey(_kBoundaryKey),
    );
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final dir = Directory(_kDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File('${dir.path}/$name')
        .writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
  });
}

/// Phone-shaped viewport (390×844 logical px @ dpr 3 — iPhone-14 class) so
/// segmented-button labels don't wrap mid-word.
void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// The seeded library as REAL Track entities (ids match the autoincrement
/// order of `_seedLibrary`, so lyrics seeds and AI `build_queue` ids line
/// up with the database rows).
List<Track> _libraryTracks() {
  final at = DateTime.utc(2024);
  final rows =
      <(String, String, String, String)>[
    ('Neon Rivers', 'Velvet Echo', 'Midnight Signals', 'Electronic'),
    ('Glass Harbour', 'Cedar Waves', 'Tidelines', 'Ambient'),
    ('Northbound', 'Velvet Echo', 'Midnight Signals', 'Electronic'),
    ('Afterglow', 'Mara Bell', 'Postcard Songs', 'Indie'),
    ('Cascade', 'Cedar Waves', 'Tidelines', 'Ambient'),
    ('Slow Tide', 'Mara Bell', 'Postcard Songs', 'Indie'),
  ];
  return List<Track>.generate(rows.length, (i) {
    final row = rows[i];
    return Track(
      id: i + 1,
      sourceId: 'local',
      sourceTrackId: 'seed:${row.$1}',
      title: row.$1,
      artist: row.$2,
      album: row.$3,
      genre: row.$4,
      durationMs: 203000 + i * 7000,
      format: 'mp3',
      addedAt: at,
      updatedAt: at,
    );
  });
}

/// Seeds the same rows as [_libraryTracks] into [db].
Future<void> _seedLibrary(AppDatabase db) async {
  for (final track in _libraryTracks()) {
    await db.tracksDao.insertTrack(
      TracksCompanion.insert(
        sourceId: track.sourceId,
        sourceTrackId: track.sourceTrackId,
        title: track.title,
        artist: track.artist,
        album: Value<String?>(track.album),
        genre: Value<String?>(track.genre),
        durationMs: track.durationMs,
        format: track.format,
        addedAt: track.addedAt,
        updatedAt: track.updatedAt,
      ),
    );
  }
}

/// Same wiring as `pumpWavelyApp` (test/app/pump_app.dart) but wraps the
/// app in a keyed [RepaintBoundary] so the harness can render the live
/// tree to a PNG — the shared harness is intentionally left untouched.
Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required AppDatabase db,
  List<Override> extraOverrides = const <Override>[],
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  _usePhoneViewport(tester);

  SharedPreferences.setMockInitialValues(<String, Object>{
    OnboardingDraft.prefsCompletedKey: 'true',
  });
  final prefs = await SharedPreferences.getInstance();
  PackageInfo.setMockInitialValues(
    appName: 'Wavely',
    packageName: 'dev.wavely.test',
    version: '1.0.0',
    buildNumber: '4',
    buildSignature: 'test',
  );

  final engine = FakePlaybackEngine();
  final container = ProviderContainer(
    overrides: <Override>[
      ...buildOverrides(db: db, prefs: prefs),
      playbackEngineProvider.overrideWithValue(engine),
      syncServiceProvider.overrideWith(
        (ref) => _IdleSyncService(db, ref.watch(settingsStoreProvider)),
      ),
      ...extraOverrides,
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: _kBoundaryKey,
        child: WavelyApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (db: db, engine: engine, container: container);
}

Future<void> _dispose(_Harness harness) async {
  harness.container.dispose();
  await harness.db.close();
}

/// Sync engine that never starts (mirror of the pump_app helper).
class _IdleSyncService extends SyncService {
  _IdleSyncService(AppDatabase db, SettingsStore store)
      : super(
          db: db,
          outboxDao: db.syncOutboxDao,
          playsDao: db.playsDao,
          tracksDao: db.tracksDao,
          settingsStore: store,
          backend: null,
        );

  @override
  Future<void> start({Stream<bool>? connectivityChanges}) async {}
}

void main() {
  testWidgets('local — library with a live mini-player (plus home capture)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final scanner = _SeedingScanner(
      db: db,
      pickedRoot: '/music',
      tracks: _libraryTracks()
          .map(
            (t) => TracksCompanion.insert(
              sourceId: t.sourceId,
              sourceTrackId: t.sourceTrackId,
              title: t.title,
              artist: t.artist,
              album: Value<String?>(t.album),
              genre: Value<String?>(t.genre),
              durationMs: t.durationMs,
              format: t.format,
              addedAt: t.addedAt,
              updatedAt: t.updatedAt,
            ),
          )
          .toList(),
    );
    final harness = await _pumpApp(
      tester,
      db: db,
      extraOverrides: <Override>[
        libraryScannerProvider.overrideWithValue(scanner),
      ],
    );
    addTearDown(() => _dispose(harness));

    // The app boots into the Home branch; the Local branch owns the
    // library. Populate the library through the app's REAL scan flow
    // (Local tab → Add folder → scan → invalidate → list refresh).
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add folder').first);
    await tester.pumpAndSettle();
    // Selecting Folders (5th of 9 tabs) scrolled the bar; bring Songs back.
    await tester.fling(find.byType(TabBar), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Songs'));
    await tester.pumpAndSettle();

    // Start playback of the first track so the mini-player is live.
    await harness.container.read(queueManagerProvider.notifier).setQueue(
          _libraryTracks(),
        );
    await harness.container.read(queueManagerProvider.notifier).play();
    harness.engine.emitPosition(const Duration(seconds: 42));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);
    // Both the track tile and the mini-player show the playing track.
    expect(find.text('Neon Rivers'), findsNWidgets(2));

    await _capture(tester, 'local.png');

    // Home capture: the same session, now with "Jump back in" populated by
    // the real play + the mini-player still live.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    // At least the "Jump back in" card shows the playing track (the mini
    // player may also show it, depending on how many sections render).
    expect(find.text('Neon Rivers'), findsWidgets);

    await _capture(tester, 'home.png');
  });

  testWidgets('now_playing — full screen player', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final harness = await _pumpApp(tester, db: db);
    addTearDown(() => _dispose(harness));

    await harness.container.read(queueManagerProvider.notifier).setQueue(
          _libraryTracks(),
        );
    await harness.container.read(queueManagerProvider.notifier).play();
    harness.engine.emitState(PlaybackState.playing);
    harness.engine.emitPosition(const Duration(seconds: 42));
    await tester.pumpAndSettle();

    harness.container.read(routerProvider).go('/now-playing');
    await tester.pumpAndSettle();

    expect(find.text('Neon Rivers'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    await _capture(tester, 'now_playing.png');
  });

  testWidgets('synced_lyrics — overlay highlighting the active line',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedLibrary(db);
    // Seed the REAL DriftLyricsCache (wired by buildOverrides) through the
    // lyrics DAO — the overlay reads it via lyricsFutureProvider.
    await db.lyricsDao.upsert(
      trackId: 1,
      provider: 'lrclib',
      syncedLrc: '[00:01.00]City lights are breathing slow\n'
          '[00:04.00]Every window a stage of gold\n'
          '[00:07.00]And the boulevard hums below\n'
          '[00:10.00]We let the quiet take control\n'
          '[00:13.00]Midnight is a lullaby\n'
          '[00:16.00]Skyline drawn in neon dye\n',
    );
    final harness = await _pumpApp(tester, db: db);
    addTearDown(() => _dispose(harness));

    await harness.container.read(queueManagerProvider.notifier).setQueue(
          _libraryTracks(),
        );
    await harness.container.read(queueManagerProvider.notifier).play();
    harness.engine.emitState(PlaybackState.playing);
    await tester.pumpAndSettle();

    harness.container.read(routerProvider).go('/now-playing');
    await tester.pumpAndSettle();

    // Open the synced-lyrics overlay and park playback mid-song so a line
    // is highlighted.
    await tester.tap(find.byKey(const ValueKey('now-playing-cover')));
    await tester.pumpAndSettle();
    harness.engine.emitPosition(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.text('And the boulevard hums below'), findsOneWidget);

    await _capture(tester, 'synced_lyrics.png');
  });

  testWidgets('ai_chat — assistant reply with a generated queue',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedLibrary(db);
    _usePhoneViewport(tester);

    final launcher = RecordingTrackLauncher();
    final provider = ScriptedAiProvider(<AiReply>[
      const AiReply(
        text: '',
        toolCalls: <AiToolCall>[
          AiToolCall(
            id: 'c1',
            name: 'build_queue',
            argumentsJson:
                '{"track_ids":[1,2,3],"reason":"calm, ambient picks"}',
          ),
        ],
      ),
      const AiReply(
        text: 'Here is a calm mix from your library — glassy ambience, '
            'low key. Tap Play all to start.',
      ),
    ]);
    final service = AiService(
      provider: provider,
      executor: AiToolExecutor(tracksDao: db.tracksDao, launcher: launcher),
      snapshotLoader: () async =>
          '{"tracks":[],"counts":{"totalTracks":6,"artists":3,"genres":[]}}',
    );

    final container = ProviderContainer(
      overrides: <Override>[
        aiServiceProvider.overrideWithValue(service),
        trackLauncherProvider.overrideWithValue(launcher),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: _kBoundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: WavelyThemes.light(WavelyAccent.purple.colors),
            // Phase 11: delegates so localized screens resolve under test.
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AiChatScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'make me a chill mix');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Queued 3 tracks'), findsOneWidget);

    await _capture(tester, 'ai_chat.png');
  });

  testWidgets('settings — the settings screen', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final harness = await _pumpApp(tester, db: db);
    addTearDown(() => _dispose(harness));

    harness.container.read(routerProvider).go('/settings');
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);

    await _capture(tester, 'settings.png');
  });
}
