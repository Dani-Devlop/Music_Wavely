/// Stage 6 E2E — ARTEMIS Scenario 2: "Play a song, open the lyrics view,
/// verify the lyrics scroll and highlight. Then open the AI Chat, ask for
/// a 'chill' playlist, and verify a queue is generated."
///
/// Two flows over REAL screens: the synced-lyrics overlay of
/// [NowPlayingScreen] (highlighting driven by the real position stream of
/// the fake engine) and [AiChatScreen] wired to a real [AiService] whose
/// scripted provider answers the 'chill' request with a `build_queue` tool
/// call executed by the REAL [AiToolExecutor] against an in-memory library.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/ai_chat_providers.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/library/data/track_launcher.dart'
    show trackLauncherProvider;
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import '../features/lyrics/fakes.dart' show FakeLyricsCache, makeTrack;
import '../support/ai_chat_fakes.dart';
import '../support/fake_playback_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Flow 1 — synced lyrics highlight while the song plays.
// ─────────────────────────────────────────────────────────────────────────────

Future<ProviderContainer> _pumpNowPlaying(
  WidgetTester tester,
  FakePlaybackEngine engine,
) async {
  final FakeLyricsCache cache = FakeLyricsCache();
  cache.seed(
    CachedLyrics(
      trackId: 5,
      provider: 'embedded',
      syncedLrc: '[00:01.00]first light\n'
          '[00:02.00]second line\n'
          '[00:03.00]third line\n',
      offsetMs: 0,
      fetchedAt: DateTime(2024, 1, 1),
    ),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      playbackEngineProvider.overrideWithValue(engine),
      lyricsCacheProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple.colors),
        home: const NowPlayingScreen(),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('playing a song opens synced lyrics that highlight the active '
      'line as playback advances', (tester) async {
    final FakePlaybackEngine engine = FakePlaybackEngine();
    final ProviderContainer container = await _pumpNowPlaying(tester, engine);

    // "Play a song": a queued track in the real QueueManager.
    await container.read(queueManagerProvider.notifier).setQueue(<Track>[
      makeTrack(
        id: 5,
        title: 'Neon Skyline',
        artist: 'Aurora Waves',
        durationMs: 180000,
      ),
    ]);
    await tester.pumpAndSettle();

    // "Open the lyrics view": the cover toggles the synced-lyrics overlay.
    await tester.tap(find.byKey(const ValueKey('now-playing-cover')));
    await tester.pumpAndSettle();

    // All three lines render.
    expect(find.text('first light'), findsOneWidget);
    expect(find.text('second line'), findsOneWidget);
    expect(find.text('third line'), findsOneWidget);
    // The synced controls exist.
    expect(find.text('Adjust offset'), findsOneWidget);

    // Before any position event nothing is active (all lines share the
    // neighbour weight).
    final TextStyle before =
        tester.widget<Text>(find.text('second line')).style!;
    expect(before.fontWeight, isNot(FontWeight.w600));

    // Playback advances past the second line's timestamp → the overlay
    // highlights it (accent colour + semibold) and de-emphasises others.
    engine.emitPosition(const Duration(seconds: 2, milliseconds: 100));
    await tester.pumpAndSettle();

    final TextStyle current =
        tester.widget<Text>(find.text('second line')).style!;
    expect(current.fontWeight, FontWeight.w600);
    expect(
      current.color,
      tester
          .element(find.text('second line'))
          .wavelyColors
          .accentColors
          .accent,
    );
    final TextStyle inactive =
        tester.widget<Text>(find.text('third line')).style!;
    expect(inactive.fontWeight, isNot(FontWeight.w600));
  });

  // ─────────────────────────────────────────────────────────────────────
  // Flow 2 — AI chat builds a queue for a 'chill' request.
  // ─────────────────────────────────────────────────────────────────────

  late AppDatabase db;
  late RecordingTrackLauncher launcher;

  AiService buildService(ScriptedAiProvider provider) => AiService(
        provider: provider,
        executor: AiToolExecutor(tracksDao: db.tracksDao, launcher: launcher),
        snapshotLoader: () async =>
            '{"tracks":[],"counts":{"totalTracks":4,"artists":2,"genres":[]}}',
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    const List<String> titles = <String>[
      'Slow Tide',
      'Velvet Hours',
      'Low Light',
      'Amber Drift',
    ];
    for (int i = 0; i < titles.length; i++) {
      await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'local',
          sourceTrackId: 's-${i + 1}',
          title: titles[i],
          artist: 'Chill Collective',
          durationMs: 190000 + i,
          format: 'mp3',
          addedAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
    }
    launcher = RecordingTrackLauncher();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets("asking the AI chat for a 'chill' playlist generates a queue "
      'and Play all hands it to playback', (tester) async {
    final ScriptedAiProvider provider = ScriptedAiProvider(<AiReply>[
      AiReply(
        text: '',
        toolCalls: <AiToolCall>[
          const AiToolCall(
            id: 'c1',
            name: 'build_queue',
            argumentsJson:
                '{"track_ids":[1,2,3,4],"reason":"chill mix for you"}',
          ),
        ],
      ),
      const AiReply(text: 'Here is a chill mix for you.'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          aiServiceProvider.overrideWithValue(buildService(provider)),
          trackLauncherProvider.overrideWithValue(launcher),
        ],
        child: MaterialApp(
          theme: WavelyThemes.light(WavelyAccent.purple.colors),
          home: const AiChatScreen(),
        ),
      ),
    );
    await tester.pump();

    // The mood chips are the fast path for a 'chill' request.
    final Finder chillChip = find.widgetWithText(ChoiceChip, 'chill');
    expect(chillChip, findsOneWidget);
    await tester.tap(chillChip);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'chill playlist please');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The assistant executed the build_queue tool against the real
    // executor: the queue card renders with the queued-track count.
    expect(_bubbleText('Here is a chill mix for you.'), findsWidgets);
    expect(find.text('Queued 4 tracks'), findsOneWidget);
    expect(find.text('Play all'), findsOneWidget);

    // 'Play all' launches the validated tracks.
    await tester.tap(find.text('Play all'));
    await tester.pumpAndSettle();
    expect(launcher.played, hasLength(1));
    expect(launcher.played.single, hasLength(4));
  });
}

/// Matches text inside markdown-rendered bubbles (flutter_markdown emits
/// RichText, so plain find.text is not enough for bubble bodies).
Finder _bubbleText(String substring) => find.byWidgetPredicate(
      (Widget widget) {
        if (widget is RichText) {
          return widget.text.toPlainText().contains(substring);
        }
        if (widget is Text) {
          final String plain =
              widget.data ?? widget.textSpan?.toPlainText() ?? '';
          return plain.contains(substring);
        }
        return false;
      },
    );
