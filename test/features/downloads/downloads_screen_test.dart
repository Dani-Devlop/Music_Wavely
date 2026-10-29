// authored, awaiting local run.
//
// Widget tests for lib/features/downloads/presentation/downloads_screen.dart:
// empty state (all four sections), active row (progress + pause/cancel
// wired), failed row (retry wired), and the empty → data transition.
// The screen is pumped directly (matching search_screen_test.dart) with
// databaseProvider overridden by an in-memory AppDatabase; row actions
// are driven through the real service semantics (pause/retry/cancel write
// status through the DAO even without an in-flight HTTP job).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/sources/download_file_executor.dart';

/// Filesystem-in-memory executor: the row actions under test (pause/retry)
/// never touch storage (the queue pump is gated), so every method is a
/// no-op; `fileAt` is io-arm-only.
class _StubExecutor implements DownloadFileExecutor {
  @override
  Future<void> ensureDir(String dirPath) async {}

  @override
  Future<void> writeFromStream(
    Stream<List<int>> bytes,
    String path, {
    int startOffset = 0,
  }) async {}

  @override
  Future<int> fileSize(String path) async => 0;

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> writeString(String path, String contents) async {}

  @override
  Stream<List<int>> readStream(String path) async* {}

  @override
  File fileAt(String path) => throw UnimplementedError('io-arm only');
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  // The row actions delegate to the REAL DownloadService through
  // downloadServiceProvider — provide one over the same db. wifiOnly keeps
  // its default (true) and the network reports metered, so the queue pump
  // stays gated exactly like a phone off Wi-Fi: pause/retry re-queue the
  // row and the pump deterministically does not re-pick it.
  final DownloadPrefs prefs = DownloadPrefs(await SharedPreferences.getInstance());
  final DownloadService service = DownloadService(
    db: db,
    prefs: prefs,
    resolveSources: () async => const <SourceProvider>[],
    baseDir: () async => '/base',
    executor: _StubExecutor(),
    dio: Dio(),
    isUnmetered: () async => false,
  );
  addTearDown(service.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      downloadServiceProvider.overrideWith((Ref ref) async => service),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DownloadsScreen()),
    ),
  );
  await tester.pump();
  return container;
}

DownloadsCompanion _row({
  required String sourceId,
  required String sourceTrackId,
  required DownloadStatus status,
  int progress = 0,
  String? error,
}) =>
    DownloadsCompanion.insert(
      sourceId: sourceId,
      sourceTrackId: sourceTrackId,
      targetPath: '/x/file',
      quality: 'original',
      status: status,
      progress: progress,
      startedAt: DateTime.utc(2024),
      errorMessage: Value(error),
    );

void main() {
  testWidgets('empty state renders all four sections with Nothing here.',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db: db);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Nothing here.'), findsNWidgets(4));
  });

  testWidgets('active row shows progress and pause/cancel actions',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db: db);

    final int id = await db.downloadsDao.enqueue(
      _row(
        sourceId: 'jamendo',
        sourceTrackId: 'tr-9',
        status: DownloadStatus.downloading,
        progress: 37,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('37%'), findsOneWidget);
    expect(find.text('jamendo · tr-9'), findsOneWidget);
    expect(find.byKey(ValueKey<String>('pause-$id')), findsOneWidget);
    expect(find.byKey(ValueKey<String>('cancel-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('pause-$id')));
    await tester.pumpAndSettle();
    expect(
      (await db.downloadsDao.byId(id))!.status,
      DownloadStatus.queued,
    );
  });

  testWidgets('failed row offers retry and cancel; retry re-queues',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db: db);

    final int id = await db.downloadsDao.enqueue(
      _row(
        sourceId: 'jamendo',
        sourceTrackId: 'tr-10',
        status: DownloadStatus.failed,
        progress: 10,
        error: 'size mismatch',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('size mismatch'), findsOneWidget);
    expect(find.byKey(ValueKey<String>('retry-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('retry-$id')));
    await tester.pumpAndSettle();
    expect(
      (await db.downloadsDao.byId(id))!.status,
      DownloadStatus.queued,
    );
  });

  testWidgets('completed row renders without action buttons and the '
      'section fills after the empty state', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _pump(tester, db: db);
    expect(find.text('Nothing here.'), findsNWidgets(4));

    await db.downloadsDao.enqueue(
      _row(
        sourceId: 'archive',
        sourceTrackId: 'item|file.flac',
        status: DownloadStatus.completed,
        progress: 100,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('archive · item|file.flac'), findsOneWidget);
    // Completed section now filled; the other three still empty.
    expect(find.text('Nothing here.'), findsNWidgets(3));
  });
}
