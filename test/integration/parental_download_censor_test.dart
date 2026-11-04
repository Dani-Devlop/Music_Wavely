// Stage 5 cross-feature regression — Scenario 1: Parental Control ×
// Download Manager.
//
// The full pipeline runs for real (only the network and the ffmpeg binary
// are faked):
//
//   DownloadService (real queue/retry/provenance logic, scripted HTTP,
//   REAL files on disk via IoDownloadFileExecutor)
//     → downloaded file becomes the track's local filePath
//       → TrackFilter verdict (explicit-content lyrics + blocked words)
//         → CensorPlanner mute windows
//           → CensorService render into the cache dir.
//
// Contract under test: the censor pipeline processes the DOWNLOADED file
// and NEVER mutates the original — the censored copy lands under the cache
// dir (`track-<id>.censored.m4a`), the download stays byte-identical, and a
// second censor round short-circuits on the cached render.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/parental/data/censor_executor.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';
import 'package:wavely/features/parental/data/censor_service.dart';
import 'package:wavely/features/parental/data/track_filter.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';
import 'package:wavely/sources/download_file_exports.dart';

/// Serves the track bytes (no network).
class _CdnAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        List<int>.generate(4096, (int i) => (i * 31 + 7) % 256),
        200,
        headers: <String, List<String>>{
          'content-length': <String>['4096'],
          Headers.contentTypeHeader: <String>['audio/mpeg'],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// Free-catalog source hosting the explicit track.
class _CatalogSource implements SourceProvider {
  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo (integration)';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async =>
      const <Track>[];

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'https://cdn.example.com/night-drive.mp3');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('service flow');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{
        'license_ccurl': 'https://creativecommons.org/licenses/by/4.0/',
      };
}

/// Stands in for the ffmpeg render: reads the downloaded file, writes a
/// re-rendered (byte-transformed) copy at [outputPath], returns Success.
/// Fails the test loudly if it is ever pointed at a missing input.
class _SimulatedRenderExecutor implements AudioCensorExecutor {
  int renderCalls = 0;
  String? lastInputPath;
  String? lastOutputPath;
  List<(int, int)>? lastRanges;

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
    try {
      final File input = File(inputPath);
      if (!input.existsSync()) {
        return const Result<String?>.err(
          Failure.storage(message: 'no local file'),
        );
      }
      final List<int> bytes = await input.readAsBytes();
      // A "render" is a new audio asset: invert every byte so the two files
      // are provably different content.
      final List<int> rendered = bytes.map((int b) => b ^ 0xFF).toList();
      final File out = File(outputPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(rendered, flush: true);
      return Result<String?>.success(outputPath);
    } on Object catch (e) {
      return Result<String?>.err(Failure.storage(message: e.toString()));
    }
  }
}

BlockedWordRow _word(String word, {int id = 1}) => BlockedWordRow(
      id: id,
      word: word,
      severity: 'moderate',
      language: null,
      addedAt: DateTime.utc(2024, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppDatabase db;
  late _SimulatedRenderExecutor renderExecutor;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wavely_stage5_s1');
    db = AppDatabase(NativeDatabase.memory());
    renderExecutor = _SimulatedRenderExecutor();
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('download → censor pipeline renders a copy, original untouched',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final DownloadPrefs prefs =
        DownloadPrefs(await SharedPreferences.getInstance());
    await prefs.setBaseDir('${tmp.path}/storage');

    final DownloadService service = DownloadService(
      db: db,
      prefs: prefs,
      resolveSources: () async => <SourceProvider>[_CatalogSource()],
      baseDir: () async => '/default',
      executor: IoDownloadFileExecutor(),
      dio: Dio()..httpClientAdapter = _CdnAdapter(),
      isUnmetered: () async => true,
    );

    final DateTime at = DateTime.utc(2024, 3, 1);
    final Track track = Track(
      id: 42,
      sourceId: 'jamendo',
      sourceTrackId: 'night-01',
      title: 'Night Drive',
      artist: 'Nova',
      genre: 'Electronic',
      durationMs: 180000,
      format: 'mp3',
      explicit: true,
      addedAt: at,
      updatedAt: at,
    );

    // ── 1. Download the explicit track ──────────────────────────────────
    // Subscribe BEFORE enqueueing: the event stream is broadcast, so events
    // fired before the subscription would be lost.
    final Future<DownloadEvent> completedFuture = service.events
        .firstWhere((DownloadEvent e) => e.status == DownloadStatus.completed)
        .timeout(const Duration(seconds: 10));
    final int rowId = await service.enqueue(track);
    final DownloadEvent completed = await completedFuture;
    expect(completed.rowId, rowId);

    final DownloadRow row = (await db.downloadsDao.byId(rowId))!;
    expect(row.status, DownloadStatus.completed);
    final File downloaded = File(row.targetPath);
    expect(downloaded.existsSync(), isTrue,
        reason: 'the download must land on real disk for the censor stage');
    expect(await downloaded.length(), 4096);

    // The downloaded file becomes the track's local filePath (what the
    // library scanner / provenance link-up produces for offline tracks).
    final Track offlineTrack = track.copyWith(filePath: row.targetPath);
    final List<int> originalBytes = await downloaded.readAsBytes();

    // ── 2. Parental gate over the track's synced lyrics ─────────────────
    final LyricsResult lyrics = LyricsResult(
      lines: <LyricLine>[
        LyricLine(
            startTime: const Duration(seconds: 30),
            text: 'we ride through the damn night'),
        LyricLine(
            startTime: const Duration(seconds: 40),
            text: 'city lights are clean and bright'),
      ],
      synced: true,
    );

    final WordMatcher matcher =
        WordMatcher(words: <BlockedWordRow>[_word('damn')]);
    final TrackFilter filter = TrackFilter(
      words: <BlockedWordRow>[_word('damn')],
      blockNoLyrics: false,
    );
    final TrackVerdict verdict = await filter.evaluate(
      track: offlineTrack,
      lyrics: lyrics,
      matcher: matcher,
    );
    expect(verdict, TrackVerdict.censorNeeded,
        reason: 'explicit lyrics must route through the censor pipeline, '
            'not block an offline download outright');

    final CensorPlan plan =
        CensorPlanner.plan(lyrics: lyrics, matcher: matcher);
    expect(plan.hasPlan, isTrue);
    expect(plan.ranges, <(int, int)>[(30000, 40000)]);

    // ── 3. Censor the DOWNLOADED file into the cache dir ────────────────
    final String cacheDir = '${tmp.path}/censor-cache';
    await Directory(cacheDir).create(recursive: true);
    final CensorService censor = CensorService(
      executor: renderExecutor,
      cacheDirProvider: () async => cacheDir,
    );

    final Result<String?> rendered =
        await censor.censorTrack(track: offlineTrack, plan: plan);

    final String? censoredPath = rendered.fold(
      onSuccess: (String? value) => value,
      onErr: (Failure f) => null,
    );
    expect(censoredPath, isNotNull, reason: 'render must succeed');
    expect(
      censoredPath,
      '$cacheDir/track-42.censored.m4a',
      reason: 'the censored copy is a NEW file under the cache dir',
    );

    final File censored = File(censoredPath!);
    expect(censored.existsSync(), isTrue);
    final List<int> censoredBytes = await censored.readAsBytes();
    expect(censoredBytes.length, originalBytes.length);
    // The render is provably different content from the original…
    expect(
      const ListEquality<int>().equals(censoredBytes, originalBytes),
      isFalse,
      reason: 'a censored render must not be a byte copy of the original',
    );

    // …and the DOWNLOADED ORIGINAL is byte-identical after the pipeline.
    expect(
      const ListEquality<int>().equals(await downloaded.readAsBytes(), originalBytes),
      isTrue,
      reason: 'the censor pipeline must never mutate the downloaded file',
    );

    // The executor really was pointed at the downloaded file.
    expect(renderExecutor.renderCalls, 1);
    expect(renderExecutor.lastInputPath, row.targetPath);
    expect(renderExecutor.lastRanges, plan.ranges);

    // ── 4. Re-run: cache short-circuit, original STILL untouched ────────
    final Result<String?> second =
        await censor.censorTrack(track: offlineTrack, plan: plan);
    expect(
      second.fold(onSuccess: (String? v) => v, onErr: (Failure f) => null),
      censoredPath,
    );
    expect(renderExecutor.renderCalls, 1,
        reason: 'second round must hit the cached render');
    expect(
      const ListEquality<int>().equals(await downloaded.readAsBytes(), originalBytes),
      isTrue,
    );

    await service.dispose();
  });

  test('download without explicit lyrics plays as-is (verdict allowed)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final DownloadPrefs prefs =
        DownloadPrefs(await SharedPreferences.getInstance());
    await prefs.setBaseDir('${tmp.path}/storage2');

    final DownloadService service = DownloadService(
      db: db,
      prefs: prefs,
      resolveSources: () async => <SourceProvider>[_CatalogSource()],
      baseDir: () async => '/default',
      executor: IoDownloadFileExecutor(),
      dio: Dio()..httpClientAdapter = _CdnAdapter(),
      isUnmetered: () async => true,
    );

    final DateTime at = DateTime.utc(2024, 3, 2);
    final Future<DownloadEvent> completedFuture1 = service.events
        .firstWhere((DownloadEvent e) => e.status == DownloadStatus.completed)
        .timeout(const Duration(seconds: 10));
    final int rowId = await service.enqueue(
      Track(
        sourceId: 'jamendo',
        sourceTrackId: 'clean-01',
        title: 'Clean Skies',
        artist: 'Nova',
        genre: 'Ambient',
        durationMs: 120000,
        format: 'mp3',
        addedAt: at,
        updatedAt: at,
      ),
    );
    await completedFuture1;

    final DownloadRow row = (await db.downloadsDao.byId(rowId))!;

    final Track offline = Track(
      id: 43,
      sourceId: 'jamendo',
      sourceTrackId: 'clean-01',
      title: 'Clean Skies',
      artist: 'Nova',
      genre: 'Ambient',
      durationMs: 120000,
      format: 'mp3',
      filePath: row.targetPath,
      addedAt: at,
      updatedAt: at,
    );
    final LyricsResult cleanLyrics = LyricsResult(
      lines: <LyricLine>[
        LyricLine(
            startTime: const Duration(seconds: 5),
            text: 'sunlight over open water'),
      ],
      synced: true,
    );
    final WordMatcher matcher =
        WordMatcher(words: <BlockedWordRow>[_word('damn')]);
    final TrackFilter filter = TrackFilter(
      words: <BlockedWordRow>[_word('damn')],
      blockNoLyrics: false,
    );

    final TrackVerdict verdict = await filter.evaluate(
      track: offline,
      lyrics: cleanLyrics,
      matcher: matcher,
    );
    expect(verdict, TrackVerdict.allowed);

    // Empty plan → the censor service is never even reached.
    final CensorPlan plan =
        CensorPlanner.plan(lyrics: cleanLyrics, matcher: matcher);
    final CensorService censor = CensorService(
      executor: renderExecutor,
      cacheDirProvider: () async => '${tmp.path}/c2',
    );
    final Result<String?> rendered =
        await censor.censorTrack(track: offline, plan: plan);
    expect(
      rendered.fold(onSuccess: (String? v) => v, onErr: (Failure f) => 'err'),
      isNull,
      reason: 'Success(null) = nothing to censor',
    );
    expect(renderExecutor.renderCalls, 0);

    await service.dispose();
  });

  test('provenance sidecar of a downloaded track survives the censor pass',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final DownloadPrefs prefs =
        DownloadPrefs(await SharedPreferences.getInstance());
    await prefs.setBaseDir('${tmp.path}/storage3');

    final DownloadService service = DownloadService(
      db: db,
      prefs: prefs,
      resolveSources: () async => <SourceProvider>[_CatalogSource()],
      baseDir: () async => '/default',
      executor: IoDownloadFileExecutor(),
      dio: Dio()..httpClientAdapter = _CdnAdapter(),
      isUnmetered: () async => true,
    );

    final DateTime at = DateTime.utc(2024, 3, 3);
    final Future<DownloadEvent> completedFuture2 = service.events
        .firstWhere((DownloadEvent e) => e.status == DownloadStatus.completed)
        .timeout(const Duration(seconds: 10));
    final int rowId = await service.enqueue(
      Track(
        sourceId: 'jamendo',
        sourceTrackId: 'night-02',
        title: 'Night Ride',
        artist: 'Nova',
        genre: 'Electronic',
        durationMs: 150000,
        format: 'mp3',
        addedAt: at,
        updatedAt: at,
      ),
    );
    await completedFuture2;

    final DownloadRow row = (await db.downloadsDao.byId(rowId))!;
    final Map<String, dynamic> provenanceBefore =
        jsonDecode(row.provenanceJson!) as Map<String, dynamic>;

    // Censor a matched plan against this downloaded file.
    final String cacheDir = '${tmp.path}/c3';
    await Directory(cacheDir).create(recursive: true);
    final LyricsResult lyrics = LyricsResult(
      lines: <LyricLine>[
        LyricLine(
            startTime: const Duration(seconds: 10),
            text: 'one damn light'),
      ],
      synced: true,
    );
    final CensorPlan plan = CensorPlanner.plan(
      lyrics: lyrics,
      matcher: WordMatcher(words: <BlockedWordRow>[_word('damn', id: 2)]),
    );
    final CensorService censor = CensorService(
      executor: renderExecutor,
      cacheDirProvider: () async => cacheDir,
    );
    final Result<String?> rendered = await censor.censorTrack(
      track: Track(
        id: 44,
        sourceId: 'jamendo',
        sourceTrackId: 'night-02',
        title: 'Night Ride',
        artist: 'Nova',
        genre: 'Electronic',
        durationMs: 150000,
        format: 'mp3',
        filePath: row.targetPath,
        addedAt: at,
        updatedAt: at,
      ),
      plan: plan,
    );
    expect(
      rendered.fold(onSuccess: (String? v) => v, onErr: (Failure f) => null),
      isNotNull,
    );

    // Provenance untouched by the censor pass (row + sidecar content).
    final DownloadRow after = (await db.downloadsDao.byId(rowId))!;
    expect(
      jsonDecode(after.provenanceJson!) as Map<String, dynamic>,
      provenanceBefore,
    );
    final File sidecar = File(
      '${row.targetPath.substring(0, row.targetPath.lastIndexOf('/'))}'
      '/night-02.wavely.json',
    );
    expect(sidecar.existsSync(), isTrue);
    final Map<String, dynamic> sidecarJson =
        jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
    expect(sidecarJson, provenanceBefore);
    expect(sidecarJson['sourceId'], 'night-02');

    await service.dispose();
  });
}
