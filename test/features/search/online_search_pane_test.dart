// authored, awaiting local run.
//
// Widget tests for
// lib/features/search/presentation/online_search_pane.dart: idle hint,
// empty results, results with source badge + quality label + download
// action (tap enqueues through the real DownloadService), failed-sources
// note and the error state. Sources are scripted; the download service
// runs over an in-memory database + in-memory executor.

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';
import 'package:wavely/features/search/domain/search_service.dart';
import 'package:wavely/features/search/presentation/online_search_pane.dart';
import 'package:wavely/sources/download_file_executor.dart';
import 'package:wavely/sources/source_providers.dart';

class _ScriptedSource implements SourceProvider {
  _ScriptedSource(this.id, this.tracks);

  @override
  final String id;

  final List<Track> tracks;

  @override
  String get displayName => 'Scripted $id';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async => tracks;

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'https://cdn/${t.sourceTrackId}');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('service-level flow');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{};
}

class _InMemoryExecutor implements DownloadFileExecutor {
  final Map<String, List<int>> files = <String, List<int>>{};

  @override
  Future<void> ensureDir(String dirPath) async {}

  @override
  Future<void> writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  }) async {
    files[path] = await bytes.fold<List<int>>(
      <int>[],
      (List<int> acc, List<int> c) => acc..addAll(c),
    );
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
    files[path] = contents.codeUnits;
  }

  @override
  File fileAt(String path) => throw UnimplementedError('io only');
}

Track _hit(String source, String id, String title, {String format = 'flac'}) {
  final DateTime now = DateTime.utc(2024);
  return Track(
    sourceId: source,
    sourceTrackId: id,
    title: title,
    artist: 'Nova',
    durationMs: 1000,
    format: format,
    addedAt: now,
    updatedAt: now,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required SearchService? searchService,
  required AppDatabase db,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final DownloadService downloadService = DownloadService(
    db: db,
    prefs: DownloadPrefs(prefs),
    resolveSources: () async => <SourceProvider>[_ScriptedSource(
      'jamendo',
      <Track>[_hit('jamendo', 'dl-1', 'DL Track')],
    )],
    baseDir: () async => '/base',
    executor: _InMemoryExecutor(),
    dio: Dio()..httpClientAdapter = _OkAdapter(),
    isUnmetered: () async => true,
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      onlineSearchServiceProvider.overrideWith(
        (Ref ref) async => searchService,
      ),
      downloadServiceProvider.overrideWith(
        (Ref ref) async => downloadService,
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: OnlineSearchPane())),
    ),
  );
  await tester.pump();
  return container;
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('idle state shows the hint', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(
      tester,
      db: db,
      searchService: SearchService(sources: <SourceProvider>[]),
    );
    expect(find.text('Search legal online sources'), findsOneWidget);
  });

  testWidgets('results render source badge, quality and download action; '
      'tap enqueues the download', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final SearchService service = SearchService(
      sources: <SourceProvider>[
        _ScriptedSource('jamendo', <Track>[_hit('jamendo', 'j-1', 'Aurora')]),
        _ScriptedSource('archive', <Track>[_hit('archive', 'a|f.flac', 'Aurora')]),
      ],
    );
    await _pump(tester, db: db, searchService: service);

    // Drive the controller the screen listens to.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineSearchPane)),
    );
    container
        .read(onlineSearchControllerProvider.notifier)
        .onQueryChanged('aurora');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Aurora'), findsNWidgets(2));
    expect(find.textContaining('FLAC'), findsNWidgets(2));
    expect(find.byKey(const ValueKey<String>('download-online-j-1')),
        findsOneWidget);

    // Pre-warm the lazily-created download service so the tap's read sees
    // a ready AsyncValue.
    await container.read(downloadServiceProvider.future);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('download-online-j-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Queued: Aurora'), findsOneWidget);
    final List<DownloadRow> rows =
        await db.downloadsDao.byStatuses(DownloadStatus.values);
    expect(rows.map((DownloadRow r) => r.sourceTrackId), contains('j-1'));
  });

  testWidgets('failed sources render the honest note',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // A service whose only source throws on every query: the round still
    // completes and the source is reported as failed.
    final SearchService failing = SearchService(
      sources: <SourceProvider>[_ThrowingSource()],
    );
    await _pump(tester, db: db, searchService: failing);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineSearchPane)),
    );
    container
        .read(onlineSearchControllerProvider.notifier)
        .onQueryChanged('x');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.textContaining('Some sources failed: bad'), findsOneWidget);
  });

  testWidgets('no sources → honest "no sources enabled" message',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db: db, searchService: null);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineSearchPane)),
    );
    container
        .read(onlineSearchControllerProvider.notifier)
        .onQueryChanged('x');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(
      find.text('No online sources are enabled.'),
      findsOneWidget,
    );
  });

  testWidgets('no results message', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(
      tester,
      db: db,
      searchService: SearchService(sources: <SourceProvider>[
        _ScriptedSource('empty', <Track>[]),
      ]),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(OnlineSearchPane)),
    );
    container
        .read(onlineSearchControllerProvider.notifier)
        .onQueryChanged('nothing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.textContaining('No online results'), findsOneWidget);
  });
}

class _ThrowingSource implements SourceProvider {
  @override
  String get id => 'bad';

  @override
  String get displayName => 'Bad';

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsDownload => true;

  @override
  bool get supportsSearch => true;

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async =>
      throw StateError('boom');

  @override
  Future<StreamUrl> resolveStream(Track t) async =>
      StreamUrl(url: 'https://x');

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('unused');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{};
}
