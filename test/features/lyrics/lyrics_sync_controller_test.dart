/// authored, awaiting local run.
///
/// Exercises `LyricsSyncController` over a manually driven position
/// stream: index transitions at line timestamps, dedupe of identical
/// indices, backwards seeks, boundary semantics (`<=`), nextTransition and
/// the inert empty-lines behaviour.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/domain/lyrics_sync_controller.dart';

LyricLine _line(int ms, String text) =>
    LyricLine(startTime: Duration(milliseconds: ms), text: text);

void main() {
  late StreamController<Duration> positions;
  late LyricsSyncController controller;
  late List<int> events;
  late StreamSubscription<int> subscription;

  Future<void> emit(Duration position) async {
    positions.add(position);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    positions = StreamController<Duration>();
  });

  tearDown(() {
    unawaited(subscription.cancel());
    controller.dispose();
    unawaited(positions.close());
  });

  /// Builds a controller over three lines at 0s / 2s / 5s and starts
  /// listening before any position is emitted.
  void buildController({List<LyricLine>? lines}) {
    controller = LyricsSyncController(
      lines: lines ??
          <LyricLine>[
            _line(0, 'a'),
            _line(2000, 'b'),
            _line(5000, 'c'),
          ],
      positionStream: positions.stream,
    );
    events = <int>[];
    subscription = controller.activeLineStream.listen(events.add);
  }

  group('transitions', () {
    test('index follows the line whose start time was passed', () async {
      buildController();

      expect(controller.activeIndex, -1);
      await emit(const Duration(milliseconds: 500));
      expect(controller.activeIndex, 0);
      await emit(const Duration(milliseconds: 2100));
      expect(controller.activeIndex, 1);
      await emit(const Duration(milliseconds: 5200));
      expect(controller.activeIndex, 2);
      expect(events, <int>[0, 1, 2]);
    });

    test('position before the first line reports -1 exactly once', () async {
      buildController();

      await emit(const Duration(milliseconds: -1));
      expect(controller.activeIndex, -1);
      expect(events, <int>[-1]);
    });

    test('identical indices are deduplicated', () async {
      buildController();

      await emit(const Duration(milliseconds: 100));
      await emit(const Duration(milliseconds: 800));
      await emit(const Duration(milliseconds: 1999));
      expect(events, <int>[0]);
    });

    test('a position exactly at a line start activates that line', () async {
      buildController();

      await emit(const Duration(seconds: 2));
      expect(controller.activeIndex, 1);
    });

    test('equal start times resolve to the last matching line', () async {
      buildController(lines: <LyricLine>[
        _line(1000, 'dup a'),
        _line(1000, 'dup b'),
        _line(2000, 'next'),
      ]);

      await emit(const Duration(milliseconds: 1500));
      expect(controller.activeIndex, 1);
    });
  });

  group('seeking', () {
    test('backwards seek re-scans from the top', () async {
      buildController();

      await emit(const Duration(seconds: 6));
      expect(controller.activeIndex, 2);
      await emit(const Duration(seconds: 1));
      expect(controller.activeIndex, 0);
      expect(events, <int>[2, 0]);
    });

    test('seek before the first line returns to -1', () async {
      buildController();

      await emit(const Duration(seconds: 6));
      await emit(const Duration(milliseconds: -1));
      expect(controller.activeIndex, -1);
      expect(events, <int>[2, -1]);
    });
  });

  group('nextTransition', () {
    test('points at the following line and nulls out after the last',
        () async {
      buildController();

      await emit(const Duration(milliseconds: 100));
      expect(controller.nextTransition, const Duration(seconds: 2));
      await emit(const Duration(seconds: 2));
      expect(controller.nextTransition, const Duration(seconds: 5));
      await emit(const Duration(seconds: 5));
      expect(controller.nextTransition, isNull);
    });
  });

  group('no lyrics', () {
    test('controller is inert: single -1, no transition, never throws',
        () async {
      buildController(lines: <LyricLine>[]);

      await emit(const Duration(seconds: 1));
      await emit(const Duration(seconds: 2));
      expect(controller.activeIndex, -1);
      expect(events, <int>[-1]);
      expect(controller.nextTransition, isNull);
    });
  });

  group('dispose', () {
    test('closes the stream and ignores late positions', () async {
      buildController();

      await emit(const Duration(seconds: 1));
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeIndex, 0);
      // Late position after dispose must not throw (subscription is
      // cancelled and the broadcast controller is closed).
      await emit(const Duration(seconds: 3));
      expect(events, <int>[0]);
    });
  });
}
