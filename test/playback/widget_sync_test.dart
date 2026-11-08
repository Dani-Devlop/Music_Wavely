// Phase 9.2 / 9.3 — WidgetSync (home widgets + quick-settings tile).
//
// Verifies the snapshot the Dart side publishes into `home_widget` storage
// (read natively by the three AppWidgetProviders and the QS tile) whenever
// the meaningful queue state changes, and that position ticks do NOT
// trigger widget updates. The `home_widget` platform channel is mocked so
// no native code runs.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/providers.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/widgets/widget_sync.dart';
import 'package:drift/native.dart';

import '../support/fake_playback_engine.dart';

/// Records `home_widget` channel traffic.
class _HomeWidgetRecorder {
  final Map<String, String> saved = <String, String>{};
  final List<String> updates = <String>[];

  void install() {
    const channel = MethodChannel('home_widget');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'saveWidgetData':
          final args = call.arguments as Map<Object?, Object?>;
          saved[args['id'] as String] = '${args['data']}';
          return true;
        case 'updateWidget':
          final args = call.arguments as Map<Object?, Object?>;
          updates.add('${args['android']}');
          return true;
      }
      return null;
    });
  }
}

Track _track({String id = 'w1'}) => Track(
      sourceId: Track.localSourceId,
      sourceTrackId: id,
      title: 'Widget Song',
      artist: 'Widget Artist',
      album: 'Widget Album',
      durationMs: 120000,
      format: 'mp3',
      filePath: '/tmp/$id.mp3',
      coverPath: '/tmp/$id.png',
      addedAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

void main() {

/// Waits for Riverpod's deferred notifications, then drains the serialized
/// push chain (re-draining when the chain grew while waiting).
Future<void> settle(WidgetSync sync) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final chain = sync.pushChain;
    await chain;
    if (identical(chain, sync.pushChain)) {
      return;
    }
  }
}

  late _HomeWidgetRecorder recorder;
  late AppDatabase db;
  late ProviderContainer container;
  late FakePlaybackEngine engine;

  setUp(() {
    recorder = _HomeWidgetRecorder()..install();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase(NativeDatabase.memory());
    engine = FakePlaybackEngine();
  });

  Future<void> mount() async {
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: <Override>[
        ...buildOverrides(db: db, prefs: prefs),
        playbackEngineProvider.overrideWithValue(engine),
        widgetSyncProvider.overrideWith(
          () => WidgetSync(forceAndroidTarget: true),
        ),
      ],
    );
    // Activates the widget publisher (keepAlive) together with the queue
    // manager it watches.
    container.read(widgetSyncProvider);
  }

  Future<void> teardown() async {
    container.dispose();
    await db.close();
  }

  test('publishes the full snapshot for the three widgets', () async {
    await mount();
    final manager = container.read(queueManagerProvider.notifier);
    await manager.setQueue([_track()]);
    engine.emitState(PlaybackState.playing);
    // Drain the serialized push chain.
    final sync = container.read(widgetSyncProvider.notifier);
    await settle(sync);

    expect(recorder.saved[WidgetDataKeys.title], 'Widget Song');
    expect(recorder.saved[WidgetDataKeys.artist], 'Widget Artist');
    expect(recorder.saved[WidgetDataKeys.album], 'Widget Album');
    expect(recorder.saved[WidgetDataKeys.coverPath], '/tmp/w1.png');
    expect(recorder.saved[WidgetDataKeys.playing], '1');
    expect(recorder.saved[WidgetDataKeys.durationMs], '120000');
    expect(recorder.updates, contains(WavelyWidgets.small));
    expect(recorder.updates, contains(WavelyWidgets.controls));
    expect(recorder.updates, contains(WavelyWidgets.large));
    await teardown();
  });

  test('pause flips the playing flag; idle clears the title', () async {
    await mount();
    final manager = container.read(queueManagerProvider.notifier);
    await manager.setQueue([_track()]);
    final sync = container.read(widgetSyncProvider.notifier);
    engine.emitState(PlaybackState.playing);
    await settle(sync);
    expect(recorder.saved[WidgetDataKeys.playing], '1');

    engine.emitState(PlaybackState.paused);
    await settle(sync);
    expect(recorder.saved[WidgetDataKeys.playing], '0');
    await teardown();
  });

  test('position ticks do not trigger widget rebuilds', () async {
    await mount();
    final manager = container.read(queueManagerProvider.notifier);
    await manager.setQueue([_track()]);
    engine.emitState(PlaybackState.playing);
    final sync = container.read(widgetSyncProvider.notifier);
    await settle(sync);

    final updatesAfterTrack = recorder.updates.length;
    engine.emitPosition(const Duration(seconds: 1));
    engine.emitPosition(const Duration(seconds: 2));
    engine.emitPosition(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(recorder.updates.length, updatesAfterTrack);
    await teardown();
  });

  test('non-Android targets never touch the channel', () async {
    final prefs = await SharedPreferences.getInstance();
    final plain = ProviderContainer(
      overrides: <Override>[
        ...buildOverrides(db: db, prefs: prefs),
        playbackEngineProvider.overrideWithValue(engine),
        // No forceAndroidTarget: the Linux test host gates the provider off.
      ],
    );
    plain.read(widgetSyncProvider);
    final manager = plain.read(queueManagerProvider.notifier);
    await manager.setQueue([_track()]);
    engine.emitState(PlaybackState.playing);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(recorder.saved, isEmpty);
    expect(recorder.updates, isEmpty);
    plain.dispose();
    await db.close();
  });
}
