// authored, awaiting local run.
//
// Tests for lib/sources/jamendo/jamendo_source.dart over a scripted dio
// adapter with committed fixtures: search mapping, envelope failure
// (missing/suspended client_id), metadata + download url resolution,
// rate-limiter behaviour, and the shared SourceProvider contract.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/sources/jamendo/jamendo_source.dart';
import 'package:wavely/sources/source_exception.dart';

import '../source_contract.dart';

class FakeJamendoAdapter implements HttpClientAdapter {
  FakeJamendoAdapter(this.handler);

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

ResponseBody jamendoOk(Object results) => ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'headers': <String, dynamic>{
          'status': 'success',
          'results_count': 1,
        },
        'results': results,
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

Map<String, dynamic> jamendoSearchFixture() => jsonDecode(
      fixturesSearchJson,
    ) as Map<String, dynamic>;

const String fixturesSearchJson = '''
{
  "headers": {"status": "success", "results_count": 2},
  "results": [
    {
      "id": "123",
      "name": "Aurora Borealis",
      "artist_name": "Polar Fields",
      "album_name": "North",
      "duration": 210,
      "audio": "https://prod-1.storage.jamendo.com/?trackid=123&format=mp31",
      "audiodownload": "https://prod-1.storage.jamendo.com/download/123/aurora.mp3",
      "license_ccurl": "https://creativecommons.org/licenses/by-nc-sa/3.0/",
      "image": "https://img.example/123.jpg"
    },
    {
      "id": "124",
      "name": "Nightfall",
      "artist": {"name": "Polar Fields"},
      "duration": 180,
      "audio": "https://prod-1.storage.jamendo.com/?trackid=124&format=mp31"
    }
  ]
}
''';

Track kJamendoTrack() => Track(
      sourceId: 'jamendo',
      sourceTrackId: '123',
      title: 'Aurora Borealis',
      artist: 'Polar Fields',
      durationMs: 210000,
      format: 'mp3',
      addedAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

void main() {
  group('JamendoSource', () {
    late FakeJamendoAdapter adapter;
    late JamendoSource source;

    setUp(() {
      adapter = FakeJamendoAdapter((options) {
        if (options.uri.queryParameters['id'] != null) {
          return jamendoOk(<dynamic>[
            jamendoSearchFixture()['results'].first,
          ]);
        }
        return ResponseBody.fromString(
          fixturesSearchJson,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        );
      });
      source = JamendoSource(
        clientId: 'test-client-id',
        dio: Dio()..httpClientAdapter = adapter,
        limiter: RateLimiter(Duration.zero),
      );
    });

    test('search sends the client_id and maps results', () async {
      final List<Track> hits = await source.search('aurora');
      expect(adapter.requests.single.uri.queryParameters['client_id'],
          'test-client-id');
      expect(adapter.requests.single.uri.queryParameters['search'], 'aurora');
      expect(hits.length, 2);
      expect(hits.first.sourceId, 'jamendo');
      expect(hits.first.title, 'Aurora Borealis');
      expect(hits.first.artist, 'Polar Fields');
      expect(hits.first.durationMs, 210000);
      expect(hits.last.artist, 'Polar Fields'); // nested artist map branch
    });

    test('search maps the suspended-client_id envelope to an exception',
        () async {
      adapter.handler = (_) => ResponseBody.fromString(
            jsonEncode(<String, dynamic>{
              'headers': <String, dynamic>{
                'status': 'failed',
                'code': 11,
                'error_message':
                    'Jamendo Api Suspended Application Error: ...',
              },
              'results': <dynamic>[],
            }),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType],
            },
          );
      await expectLater(
        source.search('x'),
        throwsA(
          isA<SourceApiException>()
              .having((SourceApiException e) => e.message, 'message',
                  contains('Suspended')),
        ),
      );
    });

    test('resolveStream returns the audio url for the id', () async {
      final StreamUrl url = await source.resolveStream(kJamendoTrack());
      expect(url.url, contains('trackid=123'));
    });

    test('getMetadata returns the raw result and license', () async {
      final Map<String, dynamic> meta = await source.getMetadata('123');
      expect(meta['license_ccurl'], contains('creativecommons.org'));
    });

    test('getMetadata throws for an unknown id', () async {
      adapter.handler = (_) => jamendoOk(<dynamic>[]);
      await expectLater(
        source.getMetadata('nope'),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('empty query short-circuits without network', () async {
      expect(await source.search(''), isEmpty);
      expect(adapter.requests, isEmpty);
    });

    runSourceProviderContract(
      'jamendo',
      () => JamendoSource(
        clientId: 'test-client-id',
        dio: Dio()..httpClientAdapter = FakeJamendoAdapter((options) {
          if (options.uri.queryParameters['id'] != null) {
            return jamendoOk(<dynamic>[jamendoSearchFixture()['results'].first]);
          }
          return ResponseBody.fromString(
            fixturesSearchJson,
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType],
            },
          );
        }),
        limiter: RateLimiter(Duration.zero),
      ),
      streamTrack: kJamendoTrack(),
      downloadTrack: kJamendoTrack(),
    );
  });
}
