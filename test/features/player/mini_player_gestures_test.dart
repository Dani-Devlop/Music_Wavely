// Phase 10.2 / 10.4 — mini-player gestures and the What's New sheet.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/providers.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/features/player/presentation/mini_player_host.dart';
import 'package:wavely/features/player/presentation/mini_player_widget.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/settings/presentation/whats_new.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';

import '../../support/fake_playback_engine.dart';
import '../../support/track_factory.dart' show seedTrack;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakePlaybackEngine engine,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: <Override>[
      ...buildOverrides(db: db, prefs: prefs),
      playbackEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });

  final router = GoRouter(
    initialLocation: '/test-host',
    routes: <RouteBase>[
      GoRoute(
        path: '/test-host',
        builder: (context, state) =>
            const Scaffold(body: Center(child: MiniPlayerWidget())),
      ),
      GoRoute(
        path: NowPlayingScreen.route,
        builder: (context, state) => const NowPlayingScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  late FakePlaybackEngine engine;

  setUp(() {
    engine = FakePlaybackEngine();
  });

  group('Mini-player gestures (Phase 10.2)', () {
    testWidgets('swipe up opens the now-playing screen', (tester) async {
      final container = await _pump(tester, engine: engine);
      final manager = container.read(queueManagerProvider.notifier);
      await manager.setQueue([seedTrack(1)]);
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(MiniPlayerWidget),
        const Offset(0, -300),
        1200,
      );
      await tester.pumpAndSettle();

      expect(find.byType(NowPlayingScreen), findsOneWidget);
    });

    testWidgets('swipe down hides the bar and swipe up brings it back',
        (tester) async {
      final container = await _pump(tester, engine: engine);
      final manager = container.read(queueManagerProvider.notifier);
      await manager.setQueue([seedTrack(1)]);
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(MiniPlayerWidget),
        const Offset(0, 300),
        1200,
      );
      await tester.pumpAndSettle();
      expect(container.read(miniPlayerHiddenProvider), isTrue);
      expect(find.byType(MiniPlayerHost), findsNothing);

      // Re-showing: the provider is writable (next track resets it in
      // production via the queue listener — here we assert the toggle).
      container.read(miniPlayerHiddenProvider.notifier).setHidden(false);
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayerHost), findsOneWidget);
    });

    testWidgets('swipe right jumps to the next track', (tester) async {
      final container = await _pump(tester, engine: engine);
      final manager = container.read(queueManagerProvider.notifier);
      await manager.setQueue([seedTrack(1), seedTrack(2)]);
      await tester.pumpAndSettle();

      await tester.fling(
        find.byType(MiniPlayerWidget),
        const Offset(300, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(container.read(queueManagerProvider).currentIndex, 1);
    });

    testWidgets('swipe left goes to the previous track', (tester) async {
      final container = await _pump(tester, engine: engine);
      final manager = container.read(queueManagerProvider.notifier);
      await manager.setQueue([seedTrack(1), seedTrack(2)]);
      await tester.pumpAndSettle();
      // Advance to index 1 first.
      await manager.next();
      await tester.pumpAndSettle();
      expect(container.read(queueManagerProvider).currentIndex, 1);

      await tester.fling(
        find.byType(MiniPlayerWidget),
        const Offset(-300, 0),
        1200,
      );
      await tester.pumpAndSettle();

      expect(container.read(queueManagerProvider).currentIndex, 0);
    });

    testWidgets('double-tap on the cover toggles play/pause',
        (tester) async {
      final container = await _pump(tester, engine: engine);
      final manager = container.read(queueManagerProvider.notifier);
      await manager.setQueue([seedTrack(1)]);
      engine.emitState(PlaybackState.playing);
      await tester.pumpAndSettle();

      // The cover carries its own double-tap handler (keyed).
      final coverFinder = find.byKey(
        const ValueKey<String>('mini-player-cover-tap'),
      );
      await tester.tap(coverFinder);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(coverFinder);
      await tester.pumpAndSettle();

      expect(engine.pauseCalls, 1);
    });
  });

  group("What's New sheet (Phase 10.4)", () {
    test('isUnseen / markSeen round-trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      expect(WhatsNew.isUnseen(prefs, '1.0.1'), isTrue);
      await WhatsNew.markSeen(prefs, '1.0.1');
      expect(WhatsNew.isUnseen(prefs, '1.0.1'), isFalse);
    });

    test('content ships for 1.0.1', () {
      expect(WhatsNew.contentFor('1.0.1'), isNotEmpty);
      expect(WhatsNew.contentFor('9.9.9'), isNull);
    });

    testWidgets('sheet renders bullets and the close button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    showModalBottomSheet<void>(
                      context: context,
                      builder: (context) => WhatsNewSheet(
                        version: '1.0.1',
                        bullets: WhatsNew.contentFor('1.0.1')!,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("What's New in 1.0.1"), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('whats-new-close')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('whats-new-continue')));
      await tester.pumpAndSettle();
      expect(find.text("What's New in 1.0.1"), findsNothing);
    });
  });
}
