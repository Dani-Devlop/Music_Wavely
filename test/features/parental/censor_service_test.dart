// CensorService orchestration tests (authored, awaiting local run).
//
// Covers the documented service flow: empty plan short-circuit, cache-dir
// resolution failure, cached-render short-circuit, missing local input,
// executor delegation (beep flag + ranges passed through), and the output
// naming contract (`track-<id>.censored.m4a` / sanitized source fallback).
// The real io-arm `localFileExists` probe is exercised against files created
// in a temp directory so the caching short-circuit is genuine.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/censor_executor.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';
import 'package:wavely/features/parental/data/censor_service.dart';

/// Records its arguments and returns a scripted result.
class _RecordingExecutor implements AudioCensorExecutor {
  _RecordingExecutor(this._result);

  final Result<String?> _result;
  int renderCalls = 0;
  String? lastInputPath;
  String? lastOutputPath;
  List<(int, int)>? lastRanges;
  bool? lastBeep;

  @override
  Future<Result<String?>> render({
    required String inputPath,
    required String outputPath,
    required List<(int, int)> muteRangesMs,
    required bool beepInsteadOfSilence,
  }) async {
    renderCalls++;
    lastInputPath = inputPath;
    lastOutputPath = outputPath;
    lastRanges = List<(int, int)>.unmodifiable(muteRangesMs);
    lastBeep = beepInsteadOfSilence;
    return _result;
  }
}

Track _track({
  int? id,
  String sourceTrackId = 'abc-123',
  String? filePath,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Track(
    id: id,
    sourceId: Track.localSourceId,
    sourceTrackId: sourceTrackId,
    title: 'Censor Me',
    artist: 'Artist',
    durationMs: 120000,
    format: 'mp3',
    filePath: filePath,
    addedAt: now,
    updatedAt: now,
  );
}

void main() {
  test('empty plan short-circuits to Success(null) without touching the '
      'cache dir or executor', () async {
    final executor = _RecordingExecutor(
      const Result<String?>.success('/out'),
    );
    var cacheDirCalls = 0;
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async {
        cacheDirCalls++;
        return '/cache';
      },
    );

    final result = await service.censorTrack(
      track: _track(id: 1, filePath: '/music/x.mp3'),
      plan: const CensorPlan(hasPlan: false, reason: 'no synced lyrics'),
    );

    expect(result.isSuccess, isTrue);
    expect(result.fold(onErr: (_) => null, onSuccess: (v) => v), isNull);
    expect(cacheDirCalls, 0, reason: 'must short-circuit before dir lookup');
    expect(executor.renderCalls, 0);
  });

  test('plan with no ranges also short-circuits to Success(null)', () async {
    final executor = _RecordingExecutor(
      const Result<String?>.success('/out'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => '/cache',
    );

    final result = await service.censorTrack(
      track: _track(id: 2),
      plan: const CensorPlan(hasPlan: true),
    );

    expect(result.isSuccess, isTrue);
    expect(result.fold(onErr: (_) => null, onSuccess: (v) => v), isNull);
    expect(executor.renderCalls, 0);
  });

  test('null cache dir → storage failure', () async {
    final executor = _RecordingExecutor(
      const Result<String?>.success('/out'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => null,
    );

    final result = await service.censorTrack(
      track: _track(id: 3),
      plan: const CensorPlan(hasPlan: true, ranges: [(0, 1000)]),
    );

    expect(result.isErr, isTrue);
    final failure = result.fold(onErr: (f) => f, onSuccess: (_) => null);
    expect(failure, isA<Failure>());
    expect(executor.renderCalls, 0);
  });

  test('existing cached render is returned without re-rendering',
      () async {
    final cache = await Directory.systemTemp.createTemp('wavely_censor');
    addTearDown(() async => cache.delete(recursive: true));
    final cached = File(
      '${cache.path}/track-7.censored.m4a',
    );
    await cached.writeAsBytes(<int>[1, 2, 3]);

    final executor = _RecordingExecutor(
      const Result<String?>.success('SHOULD NOT BE USED'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => cache.path,
    );

    final result = await service.censorTrack(
      track: _track(id: 7, filePath: '/music/in.mp3'),
      plan: const CensorPlan(hasPlan: true, ranges: [(500, 2000)]),
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.fold(onErr: (_) => null, onSuccess: (v) => v),
      cached.path,
    );
    expect(executor.renderCalls, 0);
  });

  test('track without local file → storage failure, executor untouched',
      () async {
    final executor = _RecordingExecutor(
      const Result<String?>.success('/out'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => '/cache',
    );

    final nullPathResult = await service.censorTrack(
      track: _track(id: 4, filePath: null),
      plan: const CensorPlan(hasPlan: true, ranges: [(0, 100)]),
    );
    final missingResult = await service.censorTrack(
      track: _track(id: 5, filePath: '/definitely/missing.mp3'),
      plan: const CensorPlan(hasPlan: true, ranges: [(0, 100)]),
    );

    expect(nullPathResult.isErr, isTrue);
    expect(missingResult.isErr, isTrue);
    expect(executor.renderCalls, 0);
  });

  test('happy path delegates to the executor with the beep flag and ranges',
      () async {
    final cache = await Directory.systemTemp.createTemp('wavely_censor');
    addTearDown(() async => cache.delete(recursive: true));
    final input = File('${cache.path}/input.mp3');
    await input.writeAsBytes(<int>[9, 9, 9]);

    final executor = _RecordingExecutor(
      Result<String?>.success('${cache.path}/out.m4a'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => cache.path,
      beepInsteadOfSilence: true,
    );

    final result = await service.censorTrack(
      track: _track(id: 9, filePath: input.path),
      plan: const CensorPlan(hasPlan: true, ranges: [(100, 800), (2000, 2600)]),
    );

    expect(result.isSuccess, isTrue);
    expect(executor.renderCalls, 1);
    expect(executor.lastInputPath, input.path);
    expect(executor.lastOutputPath, '${cache.path}/track-9.censored.m4a');
    expect(executor.lastRanges, [(100, 800), (2000, 2600)]);
    expect(executor.lastBeep, isTrue);
  });

  test('output name falls back to a sanitized sourceTrackId when the track '
      'has no db id', () async {
    final cache = await Directory.systemTemp.createTemp('wavely_censor');
    addTearDown(() async => cache.delete(recursive: true));
    final input = File('${cache.path}/input2.mp3');
    await input.writeAsBytes(<int>[1]);

    final executor = _RecordingExecutor(
      Result<String?>.success('${cache.path}/out.m4a'),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => cache.path,
      beepInsteadOfSilence: false,
    );

    await service.censorTrack(
      track: _track(
        sourceTrackId: 'weird/id with spaces&symbols',
        filePath: input.path,
      ),
      plan: const CensorPlan(hasPlan: true, ranges: [(0, 100)]),
    );

    expect(
      executor.lastOutputPath,
      endsWith('/track-weird_id_with_spaces_symbols.censored.m4a'),
    );
    expect(executor.lastBeep, isFalse);
  });

  test('executor failure is propagated as Err (caller falls back to the '
      'original file)', () async {
    final cache = await Directory.systemTemp.createTemp('wavely_censor');
    addTearDown(() async => cache.delete(recursive: true));
    final input = File('${cache.path}/input3.mp3');
    await input.writeAsBytes(<int>[1]);

    final executor = _RecordingExecutor(
      const Result<String?>.err(
        Failure.storage(message: 'ffmpeg exploded'),
      ),
    );
    final service = CensorService(
      executor: executor,
      cacheDirProvider: () async => cache.path,
    );

    final result = await service.censorTrack(
      track: _track(id: 11, filePath: input.path),
      plan: const CensorPlan(hasPlan: true, ranges: [(0, 100)]),
    );

    expect(result.isErr, isTrue);
    expect(executor.renderCalls, 1);
  });
}
