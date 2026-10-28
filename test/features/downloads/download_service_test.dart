// authored, awaiting local run.
//
// Tests for lib/features/downloads/data/download_service.dart over an
// in-memory DownloadFileExecutor, a scripted dio HttpClientAdapter and an
// in-memory AppDatabase:
// - successful download → file bytes, completed status, provenance sidecar
//   with sha256 checksum, progress events;
// - retry 3× with backoff then success / retry exhaustion → failed;
// - size mismatch → failed;
// - HTTP Range resume (206) and Range-ignored fallback (200 restart);
// - Wi-Fi-only gate;
// - pause / cancel / retry row transitions;
// - concurrency cap.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/sources/download_file_executor.dart';

/// Filesystem-in-memory executor (the io arm is exercised only on devices).
class InMemoryExecutor implements DownloadFileExecutor {
  final Map<String, List<int>> files = <String, List<int>>{};
  final Set<String> dirs = <String>{};
  final Set<String> deleted = <String>{};

  @override
  Future<void> ensureDir(String dirPath) async {
    dirs.add(dirPath);
  }

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
    deleted.add(path);
  }

  @override
  Stream<List<int>> readStream(String path) async* {
    final List<int>? data = files[path];
    if (data != null) {
      yield List<int>.of(data);
    }
  }

  @override
  File fileAt(String path) => throw UnimplementedError('io-arm only');
}

/// Scripted source.
class FakeSource implements SourceProvider {
  FakeSource({this.streamUrl = 'https://cdn.example.com/file.bin'});

  final String streamUrl;

  @override
  String get id => 'jamendo';

  @override
  String get displayName => 'Jamendo (fake)';

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
  Future<StreamUrl> resolveStream(Track t) async => StreamUrl(url: streamUrl);

  @override
  Future<File> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async =>
      throw UnsupportedError('service does its own streaming');

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async =>
      <String, dynamic>{
        'license_ccurl': 'https://creativecommons.org/licenses/by/4.0/',
      };
}

/// Scripted adapter: records requests, serves [body] with optional Range
/// handling, or fails [failures] times before succeeding. [lieContentLength]
/// makes the declared length wrong (size-mismatch test). [gate] holds the
/// response stream open until completed (pause/cancel/concurrency tests).
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter({
    required this.body,
    this.contentType = 'application/octet-stream',
    this.honorRange = true,
    int failures = 0,
    this.lieContentLength,
    this.gate,
  }) : _failures = failures;

  final List<int> body;
  final String contentType;
  final bool honorRange;
  final int? lieContentLength;
  int _failures;

  set failures(int v) {
    _failures = v;
  }

  int get failuresLeft => _failures;

  void resetFailures() {
    _failures = 0;
  }

  Completer<void>? gate;

  final List<RequestOptions> requests = <RequestOptions>[];
  var _openResponses = 0;

  int get openResponses => _openResponses;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_failures > 0) {
      _failures--;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'flaky network',
      );
    }
    final String? range = options.headers['Range'] as String?;
    var slice = body;
    var status = 200;
    final Map<String, String> extra = <String, String>{};
    if (range != null && honorRange) {
      final Match m = RegExp(r'bytes=(\d+)-').firstMatch(range)!;
      final int start = int.parse(m.group(1)!);
      slice = body.sublist(start);
      status = 206;
      extra['content-range'] =
          'bytes $start-${body.length - 1}/${body.length}';
    }
    final Stream<Uint8List> stream;
    if (gate == null) {
      stream = Stream<Uint8List>.value(Uint8List.fromList(slice));
    } else {
      // Broadcast: the accounting listener and dio's own subscription both
      // listen (a single-subscription stream would throw on the second).
      _openResponses++;
      final Completer<void> g = gate!;
      final Stream<Uint8List> single =
          Stream<Uint8List>.fromFuture(
        g.future.then((_) => Uint8List.fromList(slice)),
      );
      final Stream<Uint8List> broadcast = single.asBroadcastStream(
        onListen: (_) {},
        onCancel: (_) => _openResponses--,
      );
      broadcast.listen(
        (Uint8List _) {},
        onDone: () => _openResponses--,
        onError: (Object _) => _openResponses--,
        cancelOnError: true,
      );
      stream = broadcast;
    }
    final int declared = lieContentLength ?? slice.length;
    return ResponseBody(
      stream,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
        'content-length': <String>['$declared'],
        ...extra.map(
          (String k, String v) =>
              MapEntry<String, List<String>>(k, <String>[v]),
        ),
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

List<int> payload(int size) =>
    List<int>.generate(size, (int i) => (i * 31 + 7) % 251);

Track kTrack() {
  final DateTime now = DateTime.utc(2024);
  return Track(
    sourceId: 'jamendo',
    sourceTrackId: 'tr-1',
    title: 'Aurora',
    artist: '',
    durationMs: 1000,
    format: 'mp3',
    addedAt: now,
    updatedAt: now,
  );
}

const String kTargetPath =
    '/base/Music/Unknown/Unknown/Unknown/original/Aurora.mp3';
const String kSidecarPath =
    '/base/Music/Unknown/Unknown/Unknown/original/tr-1.wavely.json';

Future<DownloadService> _service(
  AppDatabase db,
  DownloadPrefs prefs,
  InMemoryExecutor executor,
  ScriptedAdapter adapter, {
  Future<bool> Function()? isUnmetered,
  Future<void> Function(int attempt)? backoff,
  int concurrency = 3,
}) async {
  await prefs.setConcurrency(concurrency);
  return DownloadService(
    db: db,
    prefs: prefs,
    resolveSources: () async => <SourceProvider>[FakeSource()],
    baseDir: () async => '/base',
    executor: executor,
    dio: Dio()..httpClientAdapter = adapter,
    isUnmetered: isUnmetered,
    backoff: backoff,
  );
}

void main() {
  late AppDatabase db;
  late InMemoryExecutor executor;
  late DownloadPrefs prefs;
  final List<DownloadEvent> events = <DownloadEvent>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = DownloadPrefs(await SharedPreferences.getInstance());
    db = AppDatabase(NativeDatabase.memory());
    executor = InMemoryExecutor();
    events.clear();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> collect(Stream<DownloadEvent> stream) async {
    stream.listen(events.add);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> waitFor(
    Stream<DownloadEvent> stream,
    DownloadStatus status,
    int rowId,
  ) =>
      stream
          .firstWhere(
            (DownloadEvent e) => e.status == status && e.rowId == rowId,
          )
          .timeout(const Duration(seconds: 5));

  test('successful download writes bytes, sidecar, provenance and events',
      () async {
    final ScriptedAdapter adapter = ScriptedAdapter(body: payload(65536));
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);

    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.completed, id);

    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.targetPath, kTargetPath);
    expect(executor.files[kTargetPath], payload(65536));
    expect(row.status, DownloadStatus.completed);
    expect(row.completedAt, isNotNull);

    final Map<String, dynamic> sidecar =
        jsonDecode(utf8.decode(executor.files[kSidecarPath]!))
            as Map<String, dynamic>;
    expect(sidecar['source'], 'jamendo');
    expect(sidecar['sourceId'], 'tr-1');
    expect(sidecar['url'], 'https://cdn.example.com/file.bin');
    expect(
      sidecar['license'],
      'https://creativecommons.org/licenses/by/4.0/',
    );
    expect(sidecar['quality'], 'original');
    expect(sidecar['downloadedAt'], isA<String>());
    final String checksum = sidecar['checksum'] as String;
    expect(isSha256Checksum(checksum), isTrue);

    // DB provenance mirrors the sidecar exactly.
    expect(jsonDecode(row.provenanceJson!), sidecar);

    // Event sequence: queued → downloading → completed.
    expect(
      events.where((DownloadEvent e) => e.rowId == id).map(
            (DownloadEvent e) => e.status,
          ),
      containsAllInOrder(<DownloadStatus>[
        DownloadStatus.queued,
        DownloadStatus.downloading,
        DownloadStatus.completed,
      ]),
    );

    expect(
      executor.dirs,
      contains('/base/Music/Unknown/Unknown/Unknown/original'),
    );
  });

  test('progress events carry percent when content-length is known',
      () async {
    final ScriptedAdapter adapter =
        ScriptedAdapter(body: payload(2 * 1024 * 1024));
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.completed, id);
    final List<DownloadEvent> progress = events
        .where(
          (DownloadEvent e) =>
              e.rowId == id &&
              e.status == DownloadStatus.downloading &&
              e.progress > 0,
        )
        .toList();
    expect(progress, isNotEmpty);
    expect(progress.last.progress, 100);
  });

  test('retries transient failures with backoff, then succeeds', () async {
    final ScriptedAdapter adapter = ScriptedAdapter(
      body: payload(1024),
      failures: 2,
    );
    final List<int> backoffAttempts = <int>[];
    final DownloadService s = await _service(
      db,
      prefs,
      executor,
      adapter,
      backoff: (int attempt) async {
        backoffAttempts.add(attempt);
      },
    );
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.completed, id);
    expect(adapter.requests.length, 3);
    expect(backoffAttempts, <int>[1, 2]);
    expect(
      (await db.downloadsDao.byId(id))!.status,
      DownloadStatus.completed,
    );
  });

  test('exhausts 3 attempts then marks failed with the error', () async {
    final ScriptedAdapter adapter = ScriptedAdapter(
      body: payload(1024),
      failures: 10,
    );
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.failed, id);
    expect(adapter.requests.length, 3);
    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.status, DownloadStatus.failed);
    expect(row.errorMessage, contains('flaky network'));
  });

  test('size mismatch against Content-Length fails the job', () async {
    final ScriptedAdapter adapter = ScriptedAdapter(
      body: payload(1024),
      lieContentLength: 2048,
    );
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.failed, id);
    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.status, DownloadStatus.failed);
    expect(row.errorMessage, contains('size mismatch'));
  });

  test('resumes from a partial file with HTTP Range (206)', () async {
    const int full = 4096;
    const int partial = 1024;
    final List<int> bytes = payload(full);
    final ScriptedAdapter adapter = ScriptedAdapter(body: bytes);
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);

    await executor.writeFromStream(
      Stream<List<int>>.fromIterable(<List<int>>[
        bytes.sublist(0, partial),
      ]),
      kTargetPath,
      startOffset: 0,
    );

    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.completed, id);

    expect(adapter.requests.single.headers['Range'], 'bytes=$partial-');
    expect(executor.files[kTargetPath], bytes);
  });

  test('falls back to a fresh download when the server ignores Range',
      () async {
    const int full = 4096;
    const int partial = 1024;
    final List<int> bytes = payload(full);
    final ScriptedAdapter adapter =
        ScriptedAdapter(body: bytes, honorRange: false);
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);

    await executor.writeFromStream(
      Stream<List<int>>.fromIterable(<List<int>>[
        bytes.sublist(0, partial),
      ]),
      kTargetPath,
      startOffset: 0,
    );

    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.completed, id);

    // No duplicated bytes: the file is exactly the payload.
    expect(executor.files[kTargetPath], bytes);
  });

  test('Wi-Fi-only gate holds jobs back on metered networks', () async {
    var unmetered = false;
    final ScriptedAdapter adapter = ScriptedAdapter(body: payload(1024));
    final DownloadService s = await _service(
      db,
      prefs,
      executor,
      adapter,
      isUnmetered: () async => unmetered,
    );
    await collect(s.events);

    await prefs.setWifiOnly(true);
    final int id = await s.enqueue(kTrack());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      (await db.downloadsDao.byId(id))!.status,
      DownloadStatus.queued,
    );
    expect(adapter.requests, isEmpty);

    unmetered = true;
    await s.pump();
    await waitFor(s.events, DownloadStatus.completed, id);
    expect(adapter.requests, isNotEmpty);
  });

  test('pause cancels the in-flight job and re-queues it', () async {
    final Completer<void> gate = Completer<void>();
    final ScriptedAdapter adapter =
        ScriptedAdapter(body: payload(4096), gate: gate);
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.openResponses, greaterThanOrEqualTo(1));

    await s.pause(id);
    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.status, DownloadStatus.queued);
    // Partial file (if any bytes landed) is kept for the resume.
    expect(
      executor.deleted.any((String p) => p.endsWith('Aurora.mp3')),
      isFalse,
    );

    // Resume: release the old gate, close it, pump again.
    gate.complete();
    adapter.gate = null;
    await s.pump();
    await waitFor(s.events, DownloadStatus.completed, id);
  });

  test('cancel deletes the partial file and marks the row canceled',
      () async {
    final Completer<void> gate = Completer<void>();
    final ScriptedAdapter adapter =
        ScriptedAdapter(body: payload(4096), gate: gate);
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(adapter.openResponses, greaterThanOrEqualTo(1));

    await s.cancel(id);
    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.status, DownloadStatus.canceled);
    expect(
      executor.deleted.any((String p) => p.endsWith('Aurora.mp3')),
      isTrue,
    );
    gate.complete();
  });

  test('retry re-queues a failed row', () async {
    final ScriptedAdapter adapter = ScriptedAdapter(
      body: payload(1024),
      failures: 10,
    );
    final DownloadService s = await _service(db, prefs, executor, adapter);
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.failed, id);

    adapter.resetFailures();
    await s.retry(id);
    await waitFor(s.events, DownloadStatus.completed, id);
    expect(
      (await db.downloadsDao.byId(id))!.status,
      DownloadStatus.completed,
    );
  });

  test('concurrency cap holds the queue at N active jobs', () async {
    final Completer<void> gate = Completer<void>();
    final ScriptedAdapter adapter =
        ScriptedAdapter(body: payload(1024), gate: gate);
    final DownloadService s = await _service(
      db,
      prefs,
      executor,
      adapter,
      concurrency: 1,
    );
    await collect(s.events);

    final int first = await s.enqueue(kTrack());
    final int second = await s.enqueue(kTrack());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final List<DownloadRow> active = await db.downloadsDao
        .byStatuses(<DownloadStatus>[DownloadStatus.downloading]);
    final List<DownloadRow> queued = await db.downloadsDao.pending();
    expect(active.map((DownloadRow r) => r.id), <int>[first]);
    expect(queued.map((DownloadRow r) => r.id), <int>[second]);

    gate.complete();
    await waitFor(s.events, DownloadStatus.completed, second);
  });

  test('enqueue on an unknown source fails honestly', () async {
    final DownloadService s = DownloadService(
      db: db,
      prefs: prefs,
      resolveSources: () async => <SourceProvider>[],
      baseDir: () async => '/base',
      executor: executor,
      dio: Dio()..httpClientAdapter = ScriptedAdapter(body: <int>[1]),
    );
    await collect(s.events);
    final int id = await s.enqueue(kTrack());
    await waitFor(s.events, DownloadStatus.failed, id);
    final DownloadRow row = (await db.downloadsDao.byId(id))!;
    expect(row.errorMessage, contains('not available'));
  });
}

/// sha256:<64 hex chars> shape check for the sidecar checksum field.
bool isSha256Checksum(String checksum) {
  final RegExp re = RegExp(r'^sha256:[0-9a-f]{64}$');
  return re.hasMatch(checksum);
}
