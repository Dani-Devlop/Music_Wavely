// authored, awaiting local run.
//
// Tests for lib/sources/archive_org/archive_org_source.dart with committed
// fixtures: search → best-audio mapping (Flac > VBR MP3 > Ogg Vorbis),
// creator list handling, duration parsing (mm:ss and seconds), stream URL
// construction, download flow, and the shared SourceProvider contract.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/sources/archive_org/archive_org_source.dart';
import 'package:wavely/sources/source_exception.dart';

import '../source_contract.dart';

class FakeArchiveAdapter implements HttpClientAdapter {
  FakeArchiveAdapter(this.handler);

  ResponseBody Function(RequestOptions options) handler;

  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody archiveJson(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Map<String, dynamic> searchFixture() =>
    jsonDecode(fixturesSearch) as Map<String, dynamic>;

Map<String, dynamic> metadataFixture() =>
    jsonDecode(fixturesMetadata) as Map<String, dynamic>;

const String fixturesSearch = '''
{
  "responseHeader": {"status": 0, "QTime": 42},
  "response": {"numFound": 2, "start": 0, "docs": [
    {"identifier": "example_audio_item", "title": "Example Audio Item",
     "creator": "Example Artist", "year": "1998"},
    {"identifier": "second_item", "title": "Second Item",
     "creator": ["Listed", "Artists"], "year": 2005}
  ]}
}
''';

const String fixturesMetadata = '''
{
  "metadata": {"identifier": "example_audio_item", "title": "Example Audio Item",
    "creator": "Example Artist", "date": "1998",
    "licenseurl": "https://creativecommons.org/licenses/by-nc-nd/3.0/"},
  "files": [
    {"name": "example_audio_item_meta.xml", "format": "Metadata"},
    {"name": "01 - First Song.flac", "format": "Flac", "title": "First Song",
     "length": "03:21", "size": 21000000},
    {"name": "01 - First Song_vbr.mp3", "format": "VBR MP3", "title": "First Song",
     "length": "203.5", "size": 4800000},
    {"name": "01 - First Song.ogg", "format": "Ogg Vorbis", "title": "First Song",
     "length": "03:21", "size": 3900000},
    {"name": "spectrogram.png", "format": "PNG"}
  ]
}
''';

void main() {
  group('ArchiveOrgFile', () {
    test('duration parses mm:ss and plain seconds', () {
      expect(
        ArchiveOrgFile.fromJson(
          <String, dynamic>{'name': 'a.flac', 'length': '03:21'},
        ).lengthSeconds,
        201,
      );
      expect(
        ArchiveOrgFile.fromJson(
          <String, dynamic>{'name': 'a.flac', 'length': '203.5'},
        ).lengthSeconds,
        204,
      );
    });

    test('isAudio covers the playable set only', () {
      expect(
        ArchiveOrgFile.fromJson(
          <String, dynamic>{'name': 'x.mp3'},
        ).isAudio,
        isTrue,
      );
      expect(
        ArchiveOrgFile.fromJson(
          <String, dynamic>{'name': 'x.ogg'},
        ).isAudio,
        isTrue,
      );
      expect(
        ArchiveOrgFile.fromJson(
          <String, dynamic>{'name': 'spectrogram.png'},
        ).isAudio,
        isFalse,
      );
    });
  });

  group('ArchiveOrgItem.bestAudio', () {
    ArchiveOrgItem itemWith(List<Map<String, dynamic>> files) =>
        ArchiveOrgItem(
          identifier: 'i',
          files: files.map(ArchiveOrgFile.fromJson).toList(),
        );

    test('prefers Flac over VBR MP3 over Ogg Vorbis', () {
      final ArchiveOrgFile? best = itemWith(<Map<String, dynamic>>[
        <String, dynamic>{'name': 'a.ogg', 'format': 'Ogg Vorbis'},
        <String, dynamic>{'name': 'a_vbr.mp3', 'format': 'VBR MP3'},
        <String, dynamic>{'name': 'a.flac', 'format': 'Flac'},
      ]).bestAudio;
      expect(best!.name, 'a.flac');
    });

    test('falls back to VBR MP3 then Ogg then any audio', () {
      expect(
        itemWith(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'a.ogg', 'format': 'Ogg Vorbis'},
          <String, dynamic>{'name': 'a_vbr.mp3', 'format': 'VBR MP3'},
        ]).bestAudio!.name,
        'a_vbr.mp3',
      );
      expect(
        itemWith(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'a.ogg', 'format': 'Ogg Vorbis'},
        ]).bestAudio!.name,
        'a.ogg',
      );
      expect(
        itemWith(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'a.m4a', 'format': '256Kbps MPEG4'},
        ]).bestAudio!.name,
        'a.m4a',
      );
      expect(
        itemWith(<Map<String, dynamic>>[
          <String, dynamic>{'name': 'meta.xml', 'format': 'Metadata'},
        ]).bestAudio,
        isNull,
      );
    });
  });

  group('ArchiveOrgSource', () {
    late FakeArchiveAdapter adapter;
    late ArchiveOrgSource source;

    setUp(() {
      adapter = FakeArchiveAdapter((options) {
        if (options.uri.host == 'archive.org' &&
            options.uri.path.startsWith('/metadata/')) {
          return archiveJson(metadataFixture());
        }
        return archiveJson(searchFixture());
      });
      source = ArchiveOrgSource(
        dio: Dio()..httpClientAdapter = adapter,
        limiter: RateLimiter(Duration.zero),
      );
    });

    test('search maps docs to one Track per item using the best audio',
        () async {
      final List<Track> hits = await source.search('example');
      expect(hits.length, 2);
      final Track first = hits.first;
      expect(first.sourceId, 'archive');
      expect(first.sourceTrackId, 'example_audio_item|01 - First Song.flac');
      expect(first.title, 'First Song');
      expect(first.artist, 'Example Artist');
      expect(first.format, 'flac');
      expect(first.durationMs, 201000);
    });

    test('search joins list-valued creators', () async {
      final List<Track> hits = await source.search('second');
      expect(hits.last.artist, 'Listed, Artists');
    });

    test('resolveStream builds the download URL from the pair id',
        () async {
      final StreamUrl url = await source.resolveStream(
        Track(
          sourceId: 'archive',
          sourceTrackId: 'example_audio_item|01 - First Song_vbr.mp3',
          title: 'x',
          artist: 'y',
          durationMs: 0,
          format: 'mp3',
          addedAt: DateTime.utc(2024),
          updatedAt: DateTime.utc(2024),
        ),
      );
      expect(
        url.url,
        'https://archive.org/download/example_audio_item/'
        '01%20-%20First%20Song_vbr.mp3',
      );
    });

    test('resolveStream rejects malformed ids', () async {
      await expectLater(
        source.resolveStream(
          Track(
            sourceId: 'archive',
            sourceTrackId: 'no-separator',
            title: 'x',
            artist: 'y',
            durationMs: 0,
            format: 'mp3',
            addedAt: DateTime.utc(2024),
            updatedAt: DateTime.utc(2024),
          ),
        ),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('getMetadata returns the raw item metadata', () async {
      final Map<String, dynamic> meta =
          await source.getMetadata('example_audio_item|01 - First Song.flac');
      expect(
        meta['metadata']['licenseurl'],
        contains('creativecommons.org'),
      );
    });

    runSourceProviderContract(
      'archive.org',
      () => ArchiveOrgSource(
        dio: Dio()..httpClientAdapter = FakeArchiveAdapter((options) {
          if (options.uri.path.startsWith('/metadata/')) {
            return archiveJson(metadataFixture());
          }
          return archiveJson(searchFixture());
        }),
        limiter: RateLimiter(Duration.zero),
      ),
      streamTrack: Track(
        sourceId: 'archive',
        sourceTrackId: 'example_audio_item|01 - First Song.flac',
        title: 'First Song',
        artist: 'Example Artist',
        durationMs: 201000,
        format: 'flac',
        addedAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      ),
      downloadTrack: Track(
        sourceId: 'archive',
        sourceTrackId: 'example_audio_item|01 - First Song.flac',
        title: 'First Song',
        artist: 'Example Artist',
        durationMs: 201000,
        format: 'flac',
        addedAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      ),
    );
  });
}
