/// authored, awaiting local run.
///
/// Exercises `LrclibLyricsProvider` over a hand-rolled fake
/// `HttpClientAdapter` (dio's injection seam — the class uses `dio`, not
/// `package:http`, so the task's MockClient suggestion is realized as the
/// equivalent dio fake). Verifies request URL building, the exact-match →
/// `/api/search` fallback on 404, and the "fetch never throws" contract.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/data/lrclib_lyrics_provider.dart';

import 'fakes.dart';

/// Fake dio transport: records every [RequestOptions] and answers with a
/// scripted [ResponseBody].
class FakeLrclibAdapter implements HttpClientAdapter {
  FakeLrclibAdapter(this.handler);

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

ResponseBody _json(Object? body, int statusCode) => ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

void main() {
  const String base = LrclibLyricsProvider.baseUrl;

  late FakeLyricsCache cache;
  late FakeLrclibAdapter adapter;
  late LrclibLyricsProvider provider;

  setUp(() {
    cache = FakeLyricsCache();
    adapter = FakeLrclibAdapter((_) => _json(<String, dynamic>{}, 200));
    final Dio dio = Dio(BaseOptions(baseUrl: base))
      ..httpClientAdapter = adapter;
    provider = LrclibLyricsProvider(dio: dio, cache: cache);
  });

  final Track track = makeTrack(
    id: 7,
    title: 'Neon Skyline',
    artist: 'Aurora Waves',
    album: 'Midnight City',
    durationMs: 180000,
  );

  group('request building', () {
    test('exact lookup hits /api/get with track, artist, album, duration',
        () async {
      adapter.handler = (_) => _json(<String, dynamic>{
            'id': 1,
            'trackName': 'Neon Skyline',
            'artistName': 'Aurora Waves',
            'albumName': 'Midnight City',
            'duration': 180,
            'instrumental': false,
            'plainLyrics': null,
            'syncedLyrics': '[00:01.00]one\n',
          }, 200);

      await provider.fetch(track);

      expect(adapter.requests, hasLength(1));
      final RequestOptions request = adapter.requests.single;
      expect(request.uri.toString(), startsWith('$base/api/get?'));
      expect(request.path, '/api/get');
      expect(request.queryParameters, <String, dynamic>{
        'track_name': 'Neon Skyline',
        'artist_name': 'Aurora Waves',
        'album_name': 'Midnight City',
        'duration': 180,
      });
      expect(request.sendTimeout, const Duration(seconds: 5));
    });

    test('fallback search hits /api/search without album/duration',
        () async {
      adapter.handler = (RequestOptions options) {
        if (options.path == '/api/get') {
          return _json(<String, dynamic>{'error': 'not found'}, 404);
        }
        return _json(<Map<String, dynamic>>[
          <String, dynamic>{
            'id': 2,
            'trackName': 'Neon Skyline',
            'artistName': 'Aurora Waves',
            'plainLyrics': 'plain words',
            'syncedLyrics': null,
          },
        ], 200);
      };

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNotNull);
      expect(result!.synced, isFalse);
      expect(adapter.requests, hasLength(2));
      final RequestOptions search = adapter.requests.last;
      expect(search.path, '/api/search');
      expect(search.queryParameters, <String, dynamic>{
        'track_name': 'Neon Skyline',
        'artist_name': 'Aurora Waves',
      });
    });

    test('album_name omitted when the track has no album', () async {
      adapter.handler = (_) => _json(<String, dynamic>{
            'syncedLyrics': '[00:01.00]x\n',
          }, 200);

      await provider.fetch(makeTrack(id: 7, title: 'T', artist: 'A'));

      expect(adapter.requests.single.queryParameters
          .containsKey('album_name'), isFalse);
    });
  });

  group('happy paths', () {
    test('synced record parses to synced lines and is cached', () async {
      const String lrc = '[00:01.00]one\n[00:02.00]two\n';
      adapter.handler = (_) =>
          _json(<String, dynamic>{'syncedLyrics': lrc, 'plainLyrics': null},
              200);

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNotNull);
      expect(result!.synced, isTrue);
      expect(result.lines, hasLength(2));
      expect(result.lines[1].text, 'two');
      expect(cache.upserts, hasLength(1));
      expect(cache.upserts.single.provider, 'lrclib');
      expect(cache.upserts.single.syncedLrc, lrc);
      expect(cache.upserts.single.plainText, isNull);
    });

    test('plain-only record parses to unsynced text and is cached',
        () async {
      adapter.handler = (_) => _json(<String, dynamic>{
            'syncedLyrics': null,
            'plainLyrics': 'just words\nhere',
          }, 200);

      final LyricsResult? result = await provider.fetch(track);

      expect(result!.synced, isFalse);
      expect(result.lines.single.text, contains('just words'));
      expect(cache.upserts.single.plainText, 'just words\nhere');
      expect(cache.upserts.single.syncedLrc, isNull);
    });

    test('whitespace-only lyric fields count as absent', () async {
      adapter.handler = (_) => _json(<String, dynamic>{
            'syncedLyrics': '   ',
            'plainLyrics': null,
          }, 200);

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNull);
      expect(cache.upserts, isEmpty);
    });
  });

  group('failure contract (fetch never throws)', () {
    test('404 on both endpoints resolves to null and caches nothing',
        () async {
      adapter.handler = (_) =>
          _json(<String, dynamic>{'error': 'not found'}, 404);

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNull);
      expect(adapter.requests.map((RequestOptions r) => r.path).toList(),
          <String>['/api/get', '/api/search']);
      expect(cache.upserts, isEmpty);
    });

    test('server error (500) does NOT fall back to search', () async {
      adapter.handler = (_) => _json(<String, dynamic>{}, 500);

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNull);
      expect(adapter.requests, hasLength(1));
    });

    test('malformed JSON resolves to null without a search fallback',
        () async {
      adapter.handler = (_) => ResponseBody.fromString(
            '{"syncedLyrics": "not closed',
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType],
            },
          );

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNull);
      expect(adapter.requests, hasLength(1));
      expect(cache.upserts, isEmpty);
    });

    test('network throw resolves to null and caches nothing', () async {
      adapter.handler = (_) => throw Exception('socket exploded');

      final LyricsResult? result = await provider.fetch(track);

      expect(result, isNull);
      expect(cache.upserts, isEmpty);
    });

    test('exact record without lyrics falls back to a lyric-bearing search',
        () async {
      adapter.handler = (RequestOptions options) {
        if (options.path == '/api/get') {
          // Instrumental hit: a valid record but without lyric payloads.
          return _json(<String, dynamic>{
            'id': 3,
            'instrumental': true,
            'plainLyrics': null,
            'syncedLyrics': null,
          }, 200);
        }
        return _json(<Map<String, dynamic>>[
          <String, dynamic>{'id': 4, 'plainLyrics': null},
          <String, dynamic>{'id': 5, 'syncedLyrics': '[00:01.00]found\n'},
        ], 200);
      };

      final LyricsResult? result = await provider.fetch(track);

      expect(result!.synced, isTrue);
      expect(result.lines.single.text, 'found');
      expect(cache.upserts.single.syncedLrc, '[00:01.00]found\n');
    });

    test('search returning only lyric-less entries resolves to null',
        () async {
      adapter.handler = (RequestOptions options) {
        if (options.path == '/api/get') {
          return _json(<String, dynamic>{}, 404);
        }
        return _json(<Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'plainLyrics': '  '},
          <String, dynamic>{'id': 10},
        ], 200);
      };

      expect(await provider.fetch(track), isNull);
      expect(cache.upserts, isEmpty);
    });

    test('cache write failures do not break lyric delivery', () async {
      cache.upsertError = Exception('disk full');
      adapter.handler = (_) =>
          _json(<String, dynamic>{'syncedLyrics': '[00:01.00]ok\n'}, 200);

      final LyricsResult? result = await provider.fetch(track);

      expect(result!.lines.single.text, 'ok');
      expect(cache.upserts, isEmpty);
    });

    test('track without an id short-circuits to null without requests',
        () async {
      final LyricsResult? result =
          await provider.fetch(makeTrack(title: 'No Id'));

      expect(result, isNull);
      expect(adapter.requests, isEmpty);
    });
  });
}
