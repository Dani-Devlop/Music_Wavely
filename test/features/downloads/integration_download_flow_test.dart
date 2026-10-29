// authored, awaiting local run.
//
// Integration test (Stage 2.1 Section 11): mock source → download → the
// file lands in the folder the template computed, with a correct
// provenance sidecar next to it. Uses an in-memory executor + database and
// a scripted dio adapter, so the whole DownloadService pipeline runs for
// real except the disk.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/features/downloads/data/download_events.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/domain/folder_template.dart';
import 'package:wavely/sources/download_file_executor.dart';

class _GeoSource implements SourceProvider {
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
      StreamUrl(url: 'https://cdn.example.com/aurora.flac');

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

class _FileExecutor implements DownloadFileExecutor {
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
    files[path] = utf8.encode(contents);
  }

  @override
  File fileAt(String path) => throw UnimplementedError('io only');
}

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromBytes(
        List<int>.generate(100000, (int i) => (i * 7) % 256),
        200,
        headers: <String, List<String>>{
          'content-length': <String>['100000'],
          Headers.contentTypeHeader: <String>['audio/flac'],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mock source → download → file in template folder + provenance',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final DownloadPrefs prefs =
        DownloadPrefs(await SharedPreferences.getInstance());
    await prefs.setBaseDir('/storage/wavely');
    final _FileExecutor executor = _FileExecutor();

    final DownloadService service = DownloadService(
      db: db,
      prefs: prefs,
      resolveSources: () async => <SourceProvider>[_GeoSource()],
      baseDir: () async => '/default',
      executor: executor,
      dio: Dio()..httpClientAdapter = _Adapter(),
      folderTemplate: FolderTemplate(
        template: 'Music/{continent}/{country}/{genre}',
        geoResolver: ArtistGeoResolver(
          lookup: (String artist) async => 'Germany',
        ),
      ),
      isUnmetered: () async => true,
    );

    final List<DownloadEvent> events = <DownloadEvent>[];
    service.events.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    final DateTime at = DateTime.utc(2024, 3, 1);
    final int rowId = await service.enqueue(
      Track(
        sourceId: 'jamendo',
        sourceTrackId: 'aur-99',
        title: 'Aurora',
        artist: 'Nova',
        genre: 'Ambient',
        durationMs: 210000,
        format: 'flac',
        addedAt: at,
        updatedAt: at,
      ),
    );

    final DownloadEvent completed = await service.events
        .firstWhere((DownloadEvent e) => e.status == DownloadStatus.completed)
        .timeout(const Duration(seconds: 5));
    expect(completed.rowId, rowId);

    // Folder: template + geo resolver + genre, plus the quality segment the
    // SERVICE appends (kept out of user templates so they stay stable across
    // quality changes); the file name carries the title.
    const String dir =
        '/storage/wavely/Music/Europe/Germany/Ambient/original';
    final String audioPath = '$dir/Aurora.flac';
    final String sidecarPath = '$dir/aur-99.wavely.json';

    expect(executor.files.keys, containsAll(<String>[audioPath, sidecarPath]));
    expect(executor.files[audioPath]!.length, 100000);

    final Map<String, dynamic> sidecar =
        jsonDecode(utf8.decode(executor.files[sidecarPath]!))
            as Map<String, dynamic>;
    expect(sidecar['source'], 'jamendo');
    expect(sidecar['sourceId'], 'aur-99');
    expect(sidecar['url'], 'https://cdn.example.com/aurora.flac');
    expect(sidecar['license'],
        'https://creativecommons.org/licenses/by/4.0/');
    expect(sidecar['quality'], 'original');
    expect(sidecar['checksum'], matches(RegExp(r'^sha256:[0-9a-f]{64}$')));

    final DownloadRow row = (await db.downloadsDao.byId(rowId))!;
    expect(row.status, DownloadStatus.completed);
    expect(row.targetPath, audioPath);
    expect(jsonDecode(row.provenanceJson!), sidecar);

    // Progress events flowed: 0 → ... → 100.
    final List<int> percents = events
        .where((DownloadEvent e) =>
            e.rowId == rowId && e.status == DownloadStatus.downloading)
        .map((DownloadEvent e) => e.progress)
        .toList();
    expect(percents, isNotEmpty);
    expect(percents.last, 100);

    await db.close();
  });
}
