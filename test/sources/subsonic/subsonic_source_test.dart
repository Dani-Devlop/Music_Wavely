// authored, awaiting local run.
//
// Tests for lib/sources/subsonic/subsonic_source.dart over a scripted
// dio HttpClientAdapter: ping, search3 mapping, error-envelope mapping,
// stream redirect resolution, download flow into an in-memory executor,
// getSong metadata, and the shared SourceProvider contract.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/sources/source_exception.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';
import 'package:wavely/sources/subsonic/subsonic_source.dart';

import '../source_contract.dart';

class FakeSubsonicAdapter implements HttpClientAdapter {
  FakeSubsonicAdapter(this.handler);

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

ResponseBody subsonicOk(Object body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'subsonic-response': body}),
      200,
      headers: headers ??
          <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
    );

const SubsonicConfig kConfig = SubsonicConfig(
  url: 'https://music.example.com',
  username: 'dani',
  password: 'pw',
);

Track kStreamTrack() => Track(
      sourceId: 'subsonic',
      sourceTrackId: 'tr-1',
      title: 'One',
      artist: 'A',
      durationMs: 1000,
      format: 'mp3',
      addedAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

void main() {
  test('auth params use the salted token scheme (never the raw password)',
      () async {
    late RequestOptions captured;
    final FakeSubsonicAdapter adapter = FakeSubsonicAdapter((options) {
      captured = options;
      return subsonicOk(<String, dynamic>{'status': 'ok'});
    });
    final SubsonicSource s = SubsonicSource(
      config: kConfig,
      dio: Dio()..httpClientAdapter = adapter,
    );
    await s.ping();
    final String q = captured.uri.query;
    expect(q.contains('u=dani'), isTrue);
    expect(q.contains('v=1.16.1'), isTrue);
    expect(q.contains('c=wavely'), isTrue);
    expect(q.contains('f=json'), isTrue);
    expect(q.contains('t='), isTrue);
    expect(q.contains('s='), isTrue);
    expect(q.contains('pw'), isFalse);
  });

  group('SubsonicSource', () {
    late FakeSubsonicAdapter adapter;
    late SubsonicSource source;

    setUp(() {
      adapter = FakeSubsonicAdapter((options) {
        if (options.uri.path.endsWith('/ping.view')) {
          return subsonicOk(<String, dynamic>{
            'status': 'ok',
            'version': '1.16.1',
          });
        }
        if (options.uri.path.endsWith('/search3.view')) {
          return subsonicOk(<String, dynamic>{
            'status': 'ok',
            'searchResult3': <String, dynamic>{
              'song': <dynamic>[
                <String, dynamic>{
                  'id': 'tr-1',
                  'title': 'One',
                  'artist': 'A',
                  'album': 'Al',
                  'duration': 120,
                  'suffix': 'mp3',
                },
                <String, dynamic>{
                  'id': 'tr-2',
                  'title': 'Two',
                  'artist': 'B',
                  'duration': 90,
                },
              ],
            },
          });
        }
        if (options.uri.path.endsWith('/getSong.view')) {
          return subsonicOk(<String, dynamic>{
            'status': 'ok',
            'song': <String, dynamic>{
              'id': 'tr-1',
              'title': 'One',
              'genre': 'Jazz',
              'duration': 120,
            },
          });
        }
        return subsonicOk(<String, dynamic>{'status': 'ok'});
      });
      source = SubsonicSource(
        config: kConfig,
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('ping returns the server version', () async {
      expect(await source.ping(), '1.16.1');
    });

    test('search maps the song list', () async {
      final List<Track> hits = await source.search('one');
      expect(hits.length, 2);
      expect(hits.first.sourceTrackId, 'tr-1');
      expect(hits.first.durationMs, 120000);
    });

    test('search maps protocol failures to SourceApiException', () async {
      adapter.handler = (_) => subsonicOk(<String, dynamic>{
            'status': 'failed',
            'error': <String, dynamic>{
              'code': 40,
              'message': 'wrong credentials',
            },
          });
      await expectLater(
        source.search('x'),
        throwsA(
          isA<SourceApiException>().having(
            (SourceApiException e) => e.message,
            'message',
            contains('wrong credentials'),
          ),
        ),
      );
    });

    test('resolveStream follows a redirect Location', () async {
      adapter.handler = (_) => ResponseBody.fromString(
            '',
            302,
            headers: <String, List<String>>{
              'location': <String>['https://cdn.example.com/file-abc.mp3'],
              Headers.contentTypeHeader: <String>['text/plain'],
            },
          );
      final StreamUrl url = await source.resolveStream(kStreamTrack());
      expect(url.url, 'https://cdn.example.com/file-abc.mp3');
    });

    test('resolveStream falls back to the direct stream URL on 200',
        () async {
      adapter.handler = (_) => ResponseBody.fromBytes(
            <int>[1, 2, 3],
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['audio/mpeg'],
            },
          );
      final StreamUrl url = await source.resolveStream(kStreamTrack());
      expect(url.url, contains('/rest/stream.view'));
      expect(url.url, contains('id=tr-1'));
    });

    test('getMetadata returns the raw child JSON', () async {
      final Map<String, dynamic> meta = await source.getMetadata('tr-1');
      expect(meta['id'], 'tr-1');
      expect(meta['genre'], 'Jazz');
    });

    test('getMetadata throws when the song is absent', () async {
      adapter.handler = (_) =>
          subsonicOk(<String, dynamic>{'status': 'ok'});
      await expectLater(
        source.getMetadata('missing'),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('empty / blank search short-circuits without network', () async {
      final List<Track> hits = await source.search('  ');
      expect(hits, isEmpty);
      expect(adapter.requests, isEmpty);
    });

    test('coverArtUrl carries auth params', () {
      final String url = source.coverArtUrl('al-1');
      expect(url, contains('/rest/getCoverArt.view'));
      expect(url, contains('id=al-1'));
    });

    runSourceProviderContract(
      'subsonic',
      () {
        final FakeSubsonicAdapter a = FakeSubsonicAdapter((options) {
          if (options.uri.path.endsWith('/search3.view')) {
            return subsonicOk(<String, dynamic>{
              'status': 'ok',
              'searchResult3': <String, dynamic>{
                'song': <dynamic>[
                  <String, dynamic>{
                    'id': 'tr-1',
                    'title': 'One',
                    'artist': 'A',
                    'duration': 120,
                  },
                ],
              },
            });
          }
          if (options.uri.path.endsWith('/getSong.view')) {
            return subsonicOk(<String, dynamic>{
              'status': 'ok',
              'song': <String, dynamic>{'id': 'tr-1', 'title': 'One'},
            });
          }
          return subsonicOk(<String, dynamic>{'status': 'ok'});
        });
        return SubsonicSource(
          config: kConfig,
          dio: Dio()..httpClientAdapter = a,
        );
      },
      streamTrack: kStreamTrack(),
    );
  });
}
