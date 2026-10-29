/// authored, awaiting local run.
///
/// Widget test of `QueueSheet` over the REAL `QueueManager` with a fake
/// engine: rows render the current queue with the current-row marker,
/// tapping a row jumps via `setQueue(tracks, startIndex:)` (real method
/// names), long-press drag reorders via `reorderQueue` without touching the
/// engine when the current track stays, horizontal swipe removes via
/// `removeFromQueue`, and the close button invokes `onClose`.
library;

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/player/presentation/queue_sheet.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

import 'fake_engine.dart';
import '../lyrics/fakes.dart';

Future<(ProviderContainer, FakePlaybackEngine)> _pumpSheet(
  WidgetTester tester, {
  required VoidCallback? onClose,
}) async {
  final FakePlaybackEngine engine = FakePlaybackEngine();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
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
          body: SafeArea(
            child: QueueSheet(onClose: onClose),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (container, engine);
}

Future<(ProviderContainer, FakePlaybackEngine)> _pumpSeeded(
  WidgetTester tester, {
  required VoidCallback? onClose,
}) async {
  final (ProviderContainer container, FakePlaybackEngine engine) =
      await _pumpSheet(tester, onClose: onClose);
  await container.read(queueManagerProvider.notifier).setQueue(<Track>[
    makeTrack(id: 1, title: 'Alpha', artist: 'A', durationMs: 90000),
    makeTrack(id: 2, title: 'Beta', artist: 'B', durationMs: 120000),
    makeTrack(id: 3, title: 'Gamma', artist: 'C', durationMs: 30000),
  ]);
  await tester.pumpAndSettle();
  return (container, engine);
}

void main() {
  testWidgets('empty queue renders the empty state', (tester) async {
    await _pumpSheet(tester, onClose: null);

    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Queue is empty'), findsOneWidget);
  });

  testWidgets('rows render the queue with the current-row marker',
      (tester) async {
    await _pumpSeeded(tester, onClose: null);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    // Index numbers for the non-current rows (current row shows the eq
    // icon instead) and durations.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
  });

  testWidgets('tapping a row jumps to it via setQueue(startIndex:)',
      (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpSeeded(tester, onClose: null);

    await tester.tap(find.text('Gamma'));
    await tester.pumpAndSettle();

    expect(
      container.read(queueManagerProvider).currentIndex,
      2,
    );
    expect(engine.setQueueStarts.last, 2);
  });

  testWidgets('long-press drag reorders without reloading the current',
      (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpSeeded(tester, onClose: null);

    // Current track is Alpha (index 0). Drag it one row down.
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(kLongPressTimeout);
    // Let the drag actually lift before moving: without settling here the
    // first moveBy lands while the drag state machine is still starting.
    await tester.pumpAndSettle();
    await gesture.moveBy(const Offset(0, 90));
    await tester.pumpAndSettle();
    // 72 px rows: 90 px moves Alpha's centre into row 1; the follow-up
    // nudge must stay inside that row (past 144 px it would drop two slots
    // and land on Gamma).
    await gesture.moveBy(const Offset(0, 10));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      container
          .read(queueManagerProvider)
          .tracks
          .map((Track t) => t.title)
          .toList(),
      <String>['Beta', 'Alpha', 'Gamma'],
    );
    // The current track followed its row move: no engine reload.
    expect(container.read(queueManagerProvider).currentIndex, 1);
    expect(engine.setQueueStarts, hasLength(1));
  });

  testWidgets('horizontal swipe removes a non-current row', (tester) async {
    final (ProviderContainer container, FakePlaybackEngine engine) =
        await _pumpSeeded(tester, onClose: null);

    await tester.drag(find.text('Gamma'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(
      container.read(queueManagerProvider).tracks.map((Track t) => t.title),
      <String>['Alpha', 'Beta'],
    );
    expect(engine.setQueueStarts, hasLength(1),
        reason: 'removing another row must not touch the engine');
  });

  testWidgets('close button invokes onClose', (tester) async {
    int closes = 0;
    await _pumpSeeded(tester, onClose: () => closes++);

    await tester.tap(find.byTooltip('Close queue'));
    await tester.pump();

    expect(closes, 1);
  });
}
