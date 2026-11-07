/// Tests for the Phase 8.2 ReplayGain scan service (fake executor +
/// in-memory Drift + scripted track source).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/audio/ffmpeg_executor.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/playback/replaygain/replay_gain_scan_service.dart';
import '../../support/track_factory.dart';

/// Executor that synthesizes per-file ebur128 summaries.
class ScriptedExecutor implements FFmpegExecutor {
  ScriptedExecutor(
    this.loudnessByPath, {
    this.failOn = const <String>{},
    this.onMeasured,
  });

  /// path → integrated loudness (LUFS).
  final Map<String, double> loudnessByPath;
  final Set<String> failOn;
  final List<String> measured = <String>[];

  /// Fires after each measurement (used to cancel mid-scan).
  void Function(int measuredCount)? onMeasured;

  @override
  bool get isAvailable => true;

  @override
  Future<FFmpegRunResult> execute(List<String> args) async {
    // [-hide_banner, -nostdin, -i, path, -filter_complex, ...]
    final String path = args[3];
    measured.add(path);
    onMeasured?.call(measured.length);
    if (failOn.contains(path)) {
      return const FFmpegRunResult(success: false, logs: 'decode error');
    }
    final double? loudness = loudnessByPath[path];
    if (loudness == null) {
      return const FFmpegRunResult(success: true, logs: 'nothing useful');
    }
    return FFmpegRunResult(
      success: true,
      logs: 'Summary:\n  Integrated loudness:\n'
          '    I:         $loudness LUFS\n'
          '  True peak:\n'
          '    Peak:      -1.0 dBFS',
    );
  }
}

/// Scripted local-library source.
class FakeTrackSource implements ReplayGainTrackSource {
  FakeTrackSource(this.tracks);

  final List<Track> tracks;

  @override
  Future<List<Track>> localTracks() async => tracks;
}

Track trackWith(int id, String path, {String? album, String? artist}) =>
    seedTrack(
      id,
      id: id,
      title: 'Track $id',
      artist: artist ?? 'Artist',
      album: album,
      filePath: path,
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('scan stores track gain + peak and skips already-scanned ids',
      () async {
    final Directory temp = await Directory.systemTemp.createTemp('rg-scan');
    addTearDown(() => temp.delete(recursive: true));
    final String pathA = '${temp.path}/a.mp3';
    final String pathB = '${temp.path}/b.mp3';
    await File(pathA).writeAsBytes(<int>[1]);
    await File(pathB).writeAsBytes(<int>[2]);

    final Track a = trackWith(11, pathA, album: 'One');
    final Track b = trackWith(12, pathB, album: 'One');
    final ScriptedExecutor executor = ScriptedExecutor(
      <String, double>{pathA: -14, pathB: -18},
    );
    final ReplayGainScanService service = ReplayGainScanService(
      executor: executor,
      db: db,
      trackSource: FakeTrackSource(<Track>[a, b]),
    );

    final ReplayGainScanState state = await service.scanLibrary();
    expect(state.running, isFalse);
    expect(state.completed, 2);
    expect(state.failed, 0);

    final ReplayGainRow? rowA = await db.replayGainDao.forTrack(11);
    expect(rowA, isNotNull);
    expect(rowA!.trackGainDb, closeTo(-4.0, 0.0001)); // -18 - (-14)
    expect(rowA.peak, closeTo(0.8912, 0.001)); // -1 dBFS
    expect(await db.replayGainDao.forTrack(12), isNotNull);

    // Second run skips both (already scanned).
    final ReplayGainScanState second = await service.scanLibrary();
    expect(second.total, 0);
    expect(executor.measured, hasLength(2));

    // rescan: true re-measures everything.
    final ReplayGainScanState third =
        await service.scanLibrary(rescan: true);
    expect(third.completed, 2);
    expect(executor.measured, hasLength(4));
  });

  test('album pass backfills album gain over multi-track albums',
      () async {
    final Directory temp = await Directory.systemTemp.createTemp('rg-album');
    addTearDown(() => temp.delete(recursive: true));
    final String pathA = '${temp.path}/a.mp3';
    final String pathB = '${temp.path}/b.mp3';
    final String pathC = '${temp.path}/c.mp3';
    for (final String path in <String>[pathA, pathB, pathC]) {
      await File(path).writeAsBytes(<int>[1]);
    }

    final ReplayGainScanService service = ReplayGainScanService(
      executor: ScriptedExecutor(<String, double>{
        pathA: -14,
        pathB: -16,
        pathC: -10, // different album
      }),
      db: db,
      trackSource: FakeTrackSource(<Track>[
        trackWith(1, pathA, album: 'Same', artist: 'X'),
        trackWith(2, pathB, album: 'Same', artist: 'X'),
        trackWith(3, pathC, album: 'Other', artist: 'X'),
      ]),
    );

    await service.scanLibrary();

    final ReplayGainRow? rowA = await db.replayGainDao.forTrack(1);
    final ReplayGainRow? rowB = await db.replayGainDao.forTrack(2);
    final ReplayGainRow? rowC = await db.replayGainDao.forTrack(3);
    // Album of two → album gain present on both members.
    expect(rowA!.albumGainDb, isNotNull);
    expect(rowA.albumGainDb, rowB!.albumGainDb);
    // Single-track "album" → no album gain backfilled.
    expect(rowC!.albumGainDb, isNull);
  });

  test('failed measurements count as failed but do not abort the scan',
      () async {
    final Directory temp = await Directory.systemTemp.createTemp('rg-fail');
    addTearDown(() => temp.delete(recursive: true));
    final String ok = '${temp.path}/ok.mp3';
    final String bad = '${temp.path}/bad.mp3';
    final String silent = '${temp.path}/silent.mp3';
    for (final String path in <String>[ok, bad, silent]) {
      await File(path).writeAsBytes(<int>[1]);
    }

    final ReplayGainScanService service = ReplayGainScanService(
      executor: ScriptedExecutor(
        <String, double>{ok: -15},
        failOn: <String>{bad},
      ),
      db: db,
      trackSource: FakeTrackSource(<Track>[
        trackWith(21, ok),
        trackWith(22, bad),
        trackWith(23, silent),
      ]),
    );

    final ReplayGainScanState state = await service.scanLibrary();
    expect(state.completed, 1);
    expect(state.failed, 2); // decode error + unparsable log
    expect(await db.replayGainDao.forTrack(21), isNotNull);
    expect(await db.replayGainDao.forTrack(22), isNull);
  });

  test('cancel stops the scan between files', () async {
    final Directory temp = await Directory.systemTemp.createTemp('rg-cancel');
    addTearDown(() => temp.delete(recursive: true));
    final Map<String, double> loudness = <String, double>{};
    final List<Track> tracks = <Track>[];
    for (var i = 0; i < 5; i++) {
      final String path = '${temp.path}/t$i.mp3';
      await File(path).writeAsBytes(<int>[1]);
      loudness[path] = -14 - i.toDouble();
      tracks.add(trackWith(30 + i, path));
    }

    final ScriptedExecutor executor = ScriptedExecutor(loudness);
    final ReplayGainScanService service = ReplayGainScanService(
      executor: executor,
      db: db,
      trackSource: FakeTrackSource(tracks),
    );

    // Cancel after the FIRST measurement: the remaining files are
    // skipped between iterations.
    executor.onMeasured = (_) => service.cancel();
    final ReplayGainScanState state = await service.scanLibrary();
    expect(state.running, isFalse);
    expect(executor.measured, hasLength(1));
    expect(state.completed, 1);
  });

  test('progress stream reports per-track updates', () async {
    final Directory temp = await Directory.systemTemp.createTemp('rg-prog');
    addTearDown(() => temp.delete(recursive: true));
    final Map<String, double> loudness = <String, double>{};
    final List<Track> tracks = <Track>[];
    for (var i = 0; i < 3; i++) {
      final String path = '${temp.path}/t$i.mp3';
      await File(path).writeAsBytes(<int>[1]);
      loudness[path] = -15;
      tracks.add(trackWith(40 + i, path));
    }

    final ReplayGainScanService service = ReplayGainScanService(
      executor: ScriptedExecutor(loudness),
      db: db,
      trackSource: FakeTrackSource(tracks),
    );

    final List<ReplayGainScanState> events = <ReplayGainScanState>[];
    final StreamSubscription<ReplayGainScanState> sub =
        service.stateStream.listen(events.add);
    addTearDown(sub.cancel);

    await service.scanLibrary();
    await service.awaitCompletion();
    // Broadcast listeners receive events on microtasks; give the final
    // (running: false) event a beat to arrive.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Start event + per-track completions + end event.
    expect(events, isNotEmpty);
    expect(events.last.running, isFalse);
    expect(events.last.progress, 1.0);
    expect(
      events.any((ReplayGainScanState e) => e.currentTrack != null),
      isTrue,
    );
  });
}
