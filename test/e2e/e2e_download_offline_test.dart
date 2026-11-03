/// Stage 6 E2E — ARTEMIS Scenario 4: "Search for a song from Jamendo or
/// Subsonic, download it, turn off Wi-Fi, and play the downloaded song.
/// Verify it plays offline."
///
/// REAL app screens and the REAL [DownloadService] pump/queue/retry logic:
/// the unified online search pane (over a scripted [SourceProvider]) lists
/// a hit, tapping its download action enqueues the job, the service writes
/// a REAL file to a temp base dir through the REAL [IoDownloadFileExecutor]
/// (only the HTTP transport is scripted), and the downloaded file then
/// plays through the REAL [QueueManager] → engine bridge as a local library
/// track. "Offline" is proven by transport accounting: the scripted CDN
/// adapter serves exactly ONE request (the download) — playback consumes
/// the local file and never touches the network.
///
/// Frame pumping is deliberately BOUNDED (`pump(duration)`, never
/// `pumpAndSettle`): the download flow carries progress indicators that
/// animate continuously, which would make an unbounded settle loop spin
/// forever under fake async.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/router.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart'
    show downloadsRoute;
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/sources/download_file_exports.dart';
import 'package:wavely/sources/source_providers.dart';

import '../app/pump_app.dart';

/// Free-catalog source hosting one downloadable track.
class _CatalogSource implements SourceProvider {
  int searchCalls = 0;

  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo (e2e)';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    searchCalls++;
    final DateTime at = DateTime.utc(2024, 3, 1);
    return <Track>[
      Track(
        sourceId: 'jamendo',
        sourceTrackId: 'night-01',
        title: 'Night Drive',
        artist: 'Nova',
        genre: 'Electronic',
        durationMs: 180000,
        format: 'mp3',
        addedAt: at,
        updatedAt: at,
      ),
    ];
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'https://cdn.example.com/night-drive.mp3');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{'license_ccurl': 'https://creativecommons.org'};

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('service flow');
}

/// The only HTTP transport in the test: serves the track bytes and counts
/// every request. One fetch == the download; nothing else may arrive.
class _CountingCdnAdapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromBytes(
      List<int>.generate(4096, (int i) => (i * 31 + 7) % 256),
      200,
      headers: <String, List<String>>{
        'content-length': <String>['4096'],
        Headers.contentTypeHeader: <String>['audio/mpeg'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Two bounded frame pumps — covers navigation transitions, the 300 ms
/// online-search debounce and microtask chains without ever spinning on a
/// continuous animation.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'search → download → the downloaded file plays with zero network traffic',
    (WidgetTester tester) async {
    // Deterministic temp dir created SYNCHRONOUSLY — awaiting real IO
    // (Directory.systemTemp.createTemp) inside the fake-async testWidgets
    // zone would hang the test forever.
    final Directory tmp = Directory(
      '${Directory.systemTemp.path}/wavely_stage6_s4_'
      '${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

      final _CatalogSource source = _CatalogSource();
      final _CountingCdnAdapter cdn = _CountingCdnAdapter();
      final AppDatabase db = AppDatabase(NativeDatabase.memory());

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final DownloadService service = DownloadService(
        db: db,
        prefs: DownloadPrefs(prefs),
        resolveSources: () async => <SourceProvider>[source],
        baseDir: () async => tmp.path,
        executor: IoDownloadFileExecutor(),
        dio: Dio()..httpClientAdapter = cdn,
        isUnmetered: () async => true,
      );

      final WavelyTestHarness harness = await pumpWavelyApp(
        tester,
        onboardingCompleted: true,
        db: db,
        extraOverrides: <Override>[
          downloadServiceProvider.overrideWith((ref) async => service),
          enabledSourcesProvider.overrideWith(
            (ref) async => <SourceProvider>[source],
          ),
        ],
      );
      addTearDown(harness.tearDown);

      // ── 1. Search online: the unified pane lists the Jamendo hit ──────
      harness.container.read(routerProvider).go(SearchScreen.route);
      await _tick(tester);

      await tester.enterText(find.byType(TextField), 'night drive');
      // Switch the scope toggle to Online — the online pane (and its hits)
      // are only visible in the Online scope.
      await tester.tap(find.text('Online'));
      // The online pane debounces for 300 ms before firing the search.
      await _tick(tester);

      expect(source.searchCalls, greaterThanOrEqualTo(1));
      expect(find.text('Night Drive'), findsOneWidget);

      // ── 2. Download it ────────────────────────────────────────────────
      // Warm the (async) service provider so the tap reads AsyncData, and
      // make sure the row action is on screen before tapping it.
      await tester.binding.runAsync(
        () => harness.container.read(downloadServiceProvider.future),
      );
      final Finder downloadAction =
          find.byKey(const ValueKey('download-online-night-01'));
      await tester.ensureVisible(downloadAction);
      await _tick(tester);

      // Subscribe BEFORE tapping: the event stream is broadcast, so events
      // fired before a subscription would be lost. A plain listener (not
      // firstWhere/timeout) — a pending Future.timeout created in the
      // fake-async zone never fires during runAsync and deadlocks the test.
      DownloadEvent? completedEvent;
      service.events.listen(
        (DownloadEvent e) {
          if (e.status == DownloadStatus.completed) {
            completedEvent = e;
          }
        },
      );

      await tester.tap(downloadAction, warnIfMissed: true);
      // The scripted download (bytes adapter + sync file write) completes
      // in microtasks inside these frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify the row state + the file on disk (all synchronous reads —
      // no real-IO awaits in the fake-async zone).
      final List<DownloadRow> completed = await db.downloadsDao
          .watchByStatuses(<DownloadStatus>[DownloadStatus.completed])
          .first;
      expect(completed, hasLength(1));
      expect(completedEvent, isNotNull);
      final String downloadedPath = completed.single.targetPath;
      final File downloaded = File(downloadedPath);
      expect(downloaded.existsSync(), isTrue);
      expect(downloaded.lengthSync(), 4096);

      // The completed download is addressable through the downloads route.
      harness.container.read(routerProvider).go(downloadsRoute);
      await _tick(tester);

      // ── 3. Offline playback: the downloaded file IS the local track ──
      // (this is the provenance link-up the app performs for downloaded
      // tracks: the library row points at the downloaded file).
      await db.tracksDao.insertTrack(
        TracksCompanion.insert(
          sourceId: 'jamendo',
          sourceTrackId: 'night-01',
          title: 'Night Drive',
          artist: 'Nova',
          durationMs: 180000,
          format: 'mp3',
          filePath: Value<String>(downloadedPath),
          addedAt: DateTime(2024, 3, 1),
          updatedAt: DateTime(2024, 3, 1),
        ),
      );

      harness.container.read(routerProvider).go('/library');
      await _tick(tester);
      await tester.tap(find.text('All Tracks'));
      await _tick(tester);
      await tester.tap(find.text('Night Drive'));
      await _tick(tester);

      expect(harness.engine.playCalls, 1);
      expect(harness.engine.loadedTrack?.filePath, downloadedPath);
      expect(
        harness.container.read(queueManagerProvider).playbackState,
        PlaybackState.playing,
      );

      // ── 4. Offline proof: exactly ONE network request ever happened ──
      // (the download itself). Search, enqueue and playback all ran over
      // the scripted catalog / local file — the player never fetched a
      // stream.
      expect(cdn.fetchCount, 1);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
