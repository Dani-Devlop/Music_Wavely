/// authored, awaiting local run.
///
/// Widget test of `MiniPlayerHost`: hidden while the queue is empty, shown
/// once a track exists, and wired to the queue manager (play/pause, next,
/// open-now-playing). The queue manager is the REAL `QueueManager` from
/// `queueManagerProvider` over a fake engine + the default in-memory
/// settings store; the shared-prefs settings graph is overridden because
/// `GlassCard` (inside MiniPlayer) watches the reduce-transparency flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/player/presentation/mini_player_host.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import 'fake_engine.dart';
import '../lyrics/fakes.dart' show makeTrack;

Future<(ProviderContainer, FakePlaybackEngine)> _pumpHost(
  WidgetTester tester,
  VoidCallback onOpenNowPlaying,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakePlaybackEngine engine = FakePlaybackEngine();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      playbackEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WavelyThemes.dark(WavelyAccent.purple),
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomSheet: MiniPlayerHost(onOpenNowPlaying: onOpenNowPlaying),
        ),
      ),
    ),
  );
  await tester.pump();
  return (container, engine);
}

void main() {
  testWidgets('renders nothing while the queue is empty', (tester) async {
    await _pumpHost(tester, () {});

    expect(find.byKey(const ValueKey<String>('mini-player-empty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mini-player')), findsNothing);
    expect(find.text('Nothing playing'), findsNothing);
  });

  testWidgets('renders the current track and flips play/pause',
      (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpHost(tester, () {});
    final QueueManager manager = container.read(queueManagerProvider.notifier);

    await manager.setQueue(<Track>[
      makeTrack(id: 1, title: 'Neon Skyline', artist: 'Aurora Waves'),
      makeTrack(id: 2, title: 'Cascade', artist: 'Aurora Waves'),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);
    expect(find.text('Neon Skyline'), findsOneWidget);
    expect(find.text('Aurora Waves'), findsOneWidget);
    // Initial load is paused.
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();

    expect(engine.playCalls, 1);
    expect(
      container.read(queueManagerProvider).playbackState,
      PlaybackState.playing,
    );
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('next advances the queue and reloads the engine', (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpHost(tester, () {});
    final QueueManager manager = container.read(queueManagerProvider.notifier);

    await manager.setQueue(<Track>[
      makeTrack(id: 1, title: 'First'),
      makeTrack(id: 2, title: 'Second'),
    ]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(container.read(queueManagerProvider).currentIndex, 1);
    // setQueue is called for the initial load and then for the advance.
    expect(engine.setQueueStarts, <int>[0, 1]);
  });

  testWidgets('tapping the bar opens the now-playing screen', (tester) async {
    int opens = 0;
    final (ProviderContainer container, FakePlaybackEngine _) =
        await _pumpHost(tester, () => opens++);
    final QueueManager manager = container.read(queueManagerProvider.notifier);

    await manager.setQueue(<Track>[makeTrack(id: 1, title: 'First')]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('First'));
    await tester.pump();

    expect(opens, 1);
  });

  testWidgets('clearing the queue hides the bar again', (tester) async {
    final (ProviderContainer container, FakePlaybackEngine _) =
        await _pumpHost(tester, () {});
    final QueueManager manager = container.read(queueManagerProvider.notifier);

    await manager.setQueue(<Track>[makeTrack(id: 1, title: 'First')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('mini-player')), findsOneWidget);

    await manager.setQueue(<Track>[]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('mini-player-empty')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('mini-player')), findsNothing);
  });
}
