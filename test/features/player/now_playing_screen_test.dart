/// authored, awaiting local run.
///
/// Widget test of `NowPlayingScreen` over the REAL `QueueManager` (from
/// `queueManagerProvider`) with a fake `PlaybackEngine` and a seeded fake
/// `LyricsCache` so the lyrics overlay resolves without any network.
/// Verifies the title/artist/seek render, the speed + sleep-timer row
/// interactions, the transport buttons, and that tapping the cover opens
/// the synced lyrics overlay. Covers render through the io arm of
/// `local_cover` (missing file -> null provider -> token fallback), so no
/// override is needed.
library;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:drift/native.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/l10n/app_localizations.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import 'fake_engine.dart';
import '../lyrics/fakes.dart';

Future<(ProviderContainer, FakePlaybackEngine)> _pumpScreen(
  WidgetTester tester, {
  FakeLyricsCache? lyricsCache,
}) async {
  final FakePlaybackEngine engine = FakePlaybackEngine();
  final FakeLyricsCache cache = lyricsCache ?? FakeLyricsCache();
  // v1.0.2: the Musicolet player's Favorite heart reads the playlists DAO
  // — mount a memory-backed database so no platform/FS handles leak into
  // the test (a real AppDatabase would leave pending timers behind).
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      playbackEngineProvider.overrideWithValue(engine),
      lyricsCacheProvider.overrideWithValue(cache),
      databaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(container.dispose);
  // v1.0.2 responsive split: these tests exercise the MOBILE (Musicolet)
  // now-playing layout — pin a phone viewport (< 800 px).
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: WavelyThemes.dark(WavelyAccent.purple.colors),
        home: const NowPlayingScreen(),
      ),
    ),
  );
  await tester.pump();
  return (container, engine);
}

Future<(ProviderContainer, FakePlaybackEngine)> _pumpWithTrack(
  WidgetTester tester, {
  FakeLyricsCache? lyricsCache,
}) async {
  final (ProviderContainer container, FakePlaybackEngine engine) =
      await _pumpScreen(tester, lyricsCache: lyricsCache);
  await container.read(queueManagerProvider.notifier).setQueue(<Track>[
    makeTrack(
      id: 5,
      title: 'Neon Skyline',
      artist: 'Aurora Waves',
      durationMs: 180000,
    ),
  ]);
  await tester.pumpAndSettle();
  return (container, engine);
}

void main() {
  testWidgets('empty queue shows the nothing-playing state', (tester) async {
    await _pumpScreen(tester);

    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('renders title, artist, seek labels and speed row',
      (tester) async {
    await _pumpWithTrack(tester);

    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Aurora Waves'), findsOneWidget);
    // Position and duration labels (180 s -> 03:00).
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);
    // v1.0.2 Musicolet layout: the speed text moved into the 14-option
    // context sheet; transport gained Rewind / Forward / EQ.
    for (final String tooltip in <String>[
      'Shuffle',
      'Repeat',
      'Rewind',
      'Previous',
      'Play or pause',
      'Next',
      'Forward',
      'Equalizer',
      'Favorite',
      'Song info',
      'Add to queue',
      'More options',
      'Sleep timer',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
  });

  testWidgets('play button reaches the engine and flips the icon',
      (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpWithTrack(tester);

    await tester.tap(find.byTooltip('Play or pause'));
    await tester.pumpAndSettle();

    expect(engine.playCalls, 1);
    expect(
      container.read(queueManagerProvider).playbackState,
      PlaybackState.playing,
    );
  });

  testWidgets('speed menu updates the queue state', (tester) async {
    final (ProviderContainer container, FakePlaybackEngine _) =
        await _pumpWithTrack(tester);

    // v1.0.2: speed lives in the 14-option Musicolet sheet (3-dots).
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play speed and pitch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25x'));
    await tester.pumpAndSettle();

    expect(container.read(queueManagerProvider).speed, 1.25);
  });

  testWidgets('sleep timer starts from the sheet and cancels with Off',
      (tester) async {
    final (ProviderContainer container, FakePlaybackEngine _) =
        await _pumpWithTrack(tester);

    // v1.0.2 Musicolet dialog: preset buttons 0:15:00 / 1:30:00 / h:mm /
    // N=5 / N=10 / After a specific song + Cancel timer when armed.
    await tester.tap(find.byTooltip('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0:15:00'));
    await tester.pumpAndSettle();

    expect(
      container.read(queueManagerProvider).sleepTimerEndsAt,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel timer'));
    await tester.pumpAndSettle();

    expect(
      container.read(queueManagerProvider).sleepTimerEndsAt,
      isNull,
    );
  });

  testWidgets('tapping the seek slider seeks the engine', (tester) async {
    final (ProviderContainer _, FakePlaybackEngine engine) =
        await _pumpWithTrack(tester);

    await tester.tap(find.byType(Slider), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(engine.seeks, isNotEmpty);
    expect(engine.seeks.single, const Duration(seconds: 90));
  });

  testWidgets('repeat button cycles off -> all -> one', (tester) async {
    final (ProviderContainer container, FakePlaybackEngine _) =
        await _pumpWithTrack(tester);

    expect(
      container.read(queueManagerProvider).repeatMode,
      RepeatMode.off,
    );
    await tester.tap(find.byTooltip('Repeat'));
    await tester.pump();
    expect(
      container.read(queueManagerProvider).repeatMode,
      RepeatMode.all,
    );
    await tester.tap(find.byTooltip('Repeat'));
    await tester.pump();
    expect(
      container.read(queueManagerProvider).repeatMode,
      RepeatMode.one,
    );
  });

  testWidgets('tapping the cover opens the synced lyrics overlay',
      (tester) async {
    final FakeLyricsCache cache = FakeLyricsCache();
    cache.seed(CachedLyrics(
      trackId: 5,
      provider: 'embedded',
      syncedLrc: '[00:01.00]first light\n[00:02.00]second line\n',
      offsetMs: 0,
      fetchedAt: DateTime(2024, 1, 1),
    ));
    await _pumpWithTrack(tester, lyricsCache: cache);

    await tester.tap(find.byKey(const ValueKey<String>('now-playing-cover')));
    await tester.pumpAndSettle();

    expect(find.text('first light'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
    expect(find.text('Adjust offset'), findsOneWidget);
  });
}
