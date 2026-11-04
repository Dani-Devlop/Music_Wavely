// Stage 5 cross-feature regression — Scenario 5: Plugin System ×
// SourceProvider consumers.
//
// A mock plugin is injected into the plugin host next to the bundled
// local-folder plugin and registers a BROKEN source (every call throws) —
// plus a GARBAGE source (returns junk-but-typed data). Contract under test:
//
//   PluginHost.loadAll isolates a throwing init.
//     → the unified search keeps returning results from healthy sources
//       and surfaces the broken plugin as a soft failure.
//         → the download manager fails the plugin's jobs gracefully
//           (status failed + error message, no crash) and stays pumpable
//           for the next job.
//             → disposeAll isolates a throwing dispose and drops all
//               registrations.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:file_system/file_system.dart' show MemoryFileSystem;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/search/domain/search_service.dart';
import 'package:wavely/plugins/bundled/local_folder_plugin.dart';
import 'package:wavely/plugins/plugin_api.dart';
import 'package:wavely/plugins/plugin_host.dart';
import 'package:wavely/sources/download_file_executor.dart';
import 'package:wavely/sources/source_exception.dart';

/// A plugin whose init throws — the host must isolate it.
class _ThrowingPlugin implements WavelyPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.throwing',
        name: 'Throwing',
        version: '0.1.0',
        capabilities: <PluginCapability>[PluginCapability.source],
      );

  @override
  Future<void> init(PluginHostContext context) async =>
      throw StateError('boom during init');

  @override
  Future<void> dispose() async {}
}

/// A plugin whose dispose throws — the host must isolate it.
class _ThrowingDisposePlugin implements WavelyPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.throwing-dispose',
        name: 'Throwing Dispose',
        version: '0.1.0',
        capabilities: <PluginCapability>[],
      );

  @override
  Future<void> init(PluginHostContext context) async {}

  @override
  Future<void> dispose() async => throw StateError('boom during dispose');
}

/// A plugin registering a source whose EVERY call fails (a plugin that got
/// misconfigured or whose remote died after registration).
class _BrokenSourcePlugin implements WavelyPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.broken-source',
        name: 'Broken Source',
        version: '0.1.0',
        capabilities: <PluginCapability>[PluginCapability.source],
      );

  @override
  Future<void> init(PluginHostContext context) async =>
      context.registerSource(_BrokenSource());

  @override
  Future<void> dispose() async {}
}

class _BrokenSource implements SourceProvider {
  @override
  String get id => 'plugin-broken';

  @override
  String get displayName => 'Broken (mock plugin)';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => false;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async =>
      throw const SourceApiException('registry unreachable');

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      throw const SourceApiException('resolve failed');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw const SourceApiException('download failed');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      throw const SourceApiException('metadata failed');
}

/// A plugin registering a source that answers with INVALID data — empty
/// titles/artists, absurd values. Typed, so it does not throw, but nothing
/// downstream should choke on it either.
class _GarbagePlugin implements WavelyPlugin {
  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'plugin.garbage',
        name: 'Garbage Data',
        version: '0.1.0',
        capabilities: <PluginCapability>[PluginCapability.source],
      );

  @override
  Future<void> init(PluginHostContext context) async =>
      context.registerSource(_GarbageSource());

  @override
  Future<void> dispose() async {}
}

class _GarbageSource implements SourceProvider {
  @override
  String get id => 'plugin-garbage';

  @override
  String get displayName => 'Garbage (mock plugin)';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => false;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async => <Track>[
        Track(
          sourceId: 'plugin-garbage',
          sourceTrackId: 'junk-1',
          title: '',
          artist: '',
          durationMs: -5,
          format: '???',
          addedAt: DateTime.utc(2024),
          updatedAt: DateTime.utc(2024),
        ),
      ];

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'not-a-url');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('read-only plugin');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{'garbage': <Object>['not', 1, 'schema']};
}

/// Serves bytes for the healthy retry job (no network).
class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        List<int>.generate(2048, (int i) => i % 256),
        200,
        headers: <String, List<String>>{
          'content-length': <String>['2048'],
        },
      );

  @override
  void close({bool force = false}) {}
}

/// A healthy remote source the download manager falls back to.
class _GoodSource implements SourceProvider {
  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo (good)';

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
      StreamUrl(url: 'https://cdn.example.com/healthy.mp3');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('service flow');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{};
}

/// In-memory download executor (disk replaced, everything else real).
class _MemExecutor implements DownloadFileExecutor {
  final Map<String, List<int>> files = <String, List<int>>{};

  @override
  Future<void> ensureDir(String dirPath) async {}

  @override
  Future<void> writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  }) async {
    final List<int> data = files.putIfAbsent(path, () => <int>[]);
    while (data.length < startOffset) {
      data.add(0);
    }
    if (startOffset < data.length) {
      data.length = startOffset;
    }
    await for (final List<int> chunk in bytes) {
      data.addAll(chunk);
    }
  }

  @override
  Future<int> fileSize(String path) async => files[path]?.length ?? 0;

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Stream<List<int>> readStream(String path) async* {
    final List<int>? d = files[path];
    if (d != null) {
      yield List<int>.of(d);
    }
  }

  @override
  Future<void> writeString(String path, String contents) async {
    files[path] = Uint8List.fromList(contents.codeUnits);
  }

  @override
  File fileAt(String path) => throw UnimplementedError('io only');
}

MemoryFileSystem _musicFs() {
  final MemoryFileSystem fs = MemoryFileSystem();
  fs.directory('/music').createSync(recursive: true);
  fs
      .file('/music/Aurora/Nebula Drive/01 Starfield.mp3')
      .createSync(recursive: true);
  fs
      .file('/music/Aurora/Nebula Drive/02 Ion Trail.flac')
      .createSync(recursive: true);
  return fs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginHost × SourceProvider registration', () {
    test('throwing init is isolated; healthy plugins still register',
        () async {
      final PluginHost host = PluginHost(factories: <WavelyPluginFactory>[
        () => LocalFolderPlugin(folders: const <String>['/music'], fs: _musicFs()),
        () => _ThrowingPlugin(),
        () => _BrokenSourcePlugin(),
        () => _GarbagePlugin(),
      ]);

      final List<PluginLoadResult> results = await host.loadAll();
      expect(results, hasLength(4));
      expect(results[0].ok, isTrue, reason: 'bundled plugin loads');
      expect(results[1].ok, isFalse, reason: 'throwing init is isolated');
      expect(results[1].error, contains('boom during init'));
      expect(results[2].ok, isTrue, reason: 'registering a broken SOURCE is '
          'a successful load — the source fails later, at call time');
      expect(results[3].ok, isTrue);

      expect(host.registeredSources, hasLength(3));
      expect(
        host.registeredSources.map((SourceProvider s) => s.id).toSet(),
        <String>{localFolderSourceId, 'plugin-broken', 'plugin-garbage'},
      );
    });

    test('throwing dispose is isolated; registrations are dropped anyway',
        () async {
      final PluginHost host = PluginHost(factories: <WavelyPluginFactory>[
        () => _ThrowingDisposePlugin(),
        () => LocalFolderPlugin(folders: const <String>['/music'], fs: _musicFs()),
      ]);
      await host.loadAll();
      expect(host.registeredSources, hasLength(1));

      await host.disposeAll(); // must not throw
      expect(host.registeredSources, isEmpty);
      expect(host.loadedManifests, isEmpty);

      // Idempotent.
      await host.disposeAll();
    });
  });

  group('mock plugin sources × unified search', () {
    test('broken plugin source degrades to failedSources, healthy hits flow',
        () async {
      final PluginHost host = PluginHost(factories: <WavelyPluginFactory>[
        () => LocalFolderPlugin(folders: const <String>['/music'], fs: _musicFs()),
        () => _BrokenSourcePlugin(),
        () => _GarbagePlugin(),
      ]);
      await host.loadAll();

      final SearchService search = SearchService(sources: host.registeredSources);
      final UnifiedSearchResult result = await search.search('Starfield');

      // Healthy plugin results still arrive…
      expect(result.hits.map((UnifiedSearchHit h) => h.sourceId),
          contains(localFolderSourceId));
      expect(
        result.hits
            .any((UnifiedSearchHit h) => h.track.title.contains('Starfield')),
        isTrue,
      );
      // …the broken plugin is a soft failure, not a crash…
      expect(result.failedSources, contains('plugin-broken'));
      // …and the garbage plugin's invalid row merged without breaking the
      // merge/dedupe pipeline.
      expect(result.failedSources, isNot(contains('plugin-garbage')));

      // A query that only the broken plugin could answer degrades cleanly.
      final UnifiedSearchResult onlyBroken = await search.search('anything');
      expect(onlyBroken.failedSources, contains('plugin-broken'));
    });

    test('search works with ONLY mock plugin sources present', () async {
      final PluginHost host = PluginHost(factories: <WavelyPluginFactory>[
        () => _BrokenSourcePlugin(),
      ]);
      await host.loadAll();
      final SearchService search = SearchService(sources: host.registeredSources);

      final UnifiedSearchResult result = await search.search('nope');
      expect(result.hits, isEmpty);
      expect(result.failedSources, <String>['plugin-broken']);
    });
  });

  group('mock plugin sources × download manager', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('plugin job fails gracefully; the service pumps the next job',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final DownloadPrefs prefs =
          DownloadPrefs(await SharedPreferences.getInstance());
      await prefs.setBaseDir('/storage/wavely');
      await prefs.setConcurrency(1);

      final _MemExecutor executor = _MemExecutor();
      SourceProvider? injected = _BrokenSource();
      final DownloadService service = DownloadService(
        db: db,
        prefs: prefs,
        resolveSources: () async => <SourceProvider>[
          if (injected != null) injected,
        ],
        baseDir: () async => '/default',
        executor: executor,
        dio: Dio()..httpClientAdapter = _OkAdapter(),
        isUnmetered: () async => true,
      );

      final DateTime at = DateTime.utc(2024, 7, 1);
      // Subscribe BEFORE enqueueing: the event stream is broadcast, so
      // events fired before the subscription would be lost.
      final Future<DownloadEvent> failureFuture = service.events
          .firstWhere((DownloadEvent e) => e.status == DownloadStatus.failed)
          .timeout(const Duration(seconds: 10));
      // The plugin contributed this track — resolveStream will fail.
      final int brokenRowId = await service.enqueue(
        Track(
          sourceId: 'plugin-broken',
          sourceTrackId: 'broken-1',
          title: 'Broken Track',
          artist: 'Mock Plugin',
          durationMs: 60000,
          format: 'mp3',
          addedAt: at,
          updatedAt: at,
        ),
      );
      final DownloadEvent failure = await failureFuture;
      expect(failure.rowId, brokenRowId);
      expect(failure.error, isNotNull);

      final DownloadRow brokenRow = (await db.downloadsDao.byId(brokenRowId))!;
      expect(brokenRow.status, DownloadStatus.failed);
      expect(brokenRow.errorMessage, isNotNull);
      expect(executor.files, isEmpty,
          reason: 'no bytes may land for a source that never resolved');

      // The service is NOT wedged: a healthy job enqueued afterwards
      // completes normally.
      injected = _GoodSource();
      final Future<DownloadEvent> doneFuture = service.events
          .firstWhere((DownloadEvent e) => e.status == DownloadStatus.completed)
          .timeout(const Duration(seconds: 10));
      final int goodRowId = await service.enqueue(
        Track(
          sourceId: 'jamendo',
          sourceTrackId: 'good-1',
          title: 'Healthy Track',
          artist: 'Real Source',
          durationMs: 60000,
          format: 'mp3',
          addedAt: at,
          updatedAt: at,
        ),
      );
      final DownloadEvent done = await doneFuture;
      expect(done.rowId, goodRowId);
      expect(
        executor.files.keys
            .where((String p) => p.endsWith('Healthy Track.mp3')),
        isNotEmpty,
      );

      // Retry the failed plugin job (source still broken) → fails again,
      // cleanly, without touching the completed download.
      final Future<DownloadEvent> secondFailureFuture = service.events
          .firstWhere((DownloadEvent e) =>
              e.rowId == brokenRowId &&
              e.status == DownloadStatus.failed)
          .timeout(const Duration(seconds: 10));
      await service.retry(brokenRowId);
      final DownloadEvent secondFailure = await secondFailureFuture;
      expect(secondFailure.rowId, brokenRowId);
      final DownloadRow stillFailed =
          (await db.downloadsDao.byId(brokenRowId))!;
      expect(stillFailed.status, DownloadStatus.failed);
      final DownloadRow goodRow = (await db.downloadsDao.byId(goodRowId))!;
      expect(goodRow.status, DownloadStatus.completed);

      await service.dispose();
    });
  });
}
