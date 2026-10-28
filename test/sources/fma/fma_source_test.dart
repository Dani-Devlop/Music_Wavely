// authored, awaiting local run.
//
// Tests for lib/sources/fma/fma_source.dart with committed fixture HTML
// (captured from the live search page in the Stage 2.1 session): row
// parsing (track/artist/duration anchors), search mapping, the honest
// no-streaming/no-download contract, license overlay parsing, and the
// shared SourceProvider contract with expectsStreamFailure.

import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/sources/fma/fma_source.dart';
import 'package:wavely/sources/source_exception.dart';
import '../source_contract.dart';



class FakeFmaAdapter implements HttpClientAdapter {
  FakeFmaAdapter(this.handler);

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

const String kSearchHtml = '''
<html><body>
<table>
  <tr>
    <td><a href="/artist/The_Ishihara_Test/">The Ishihara Test</a></td>
    <td><a href="/track/92_Test">Test</a></td>
    <td><span>08:08</span></td>
    <td>
      <a href="javascript:;" class="js-download"
         data-url="https://freemusicarchive.org/track/92_Test/downloadOverlay/"
         title="Download"></a>
    </td>
  </tr>
  <tr>
    <td><a href="/artist/Polar_Fields/">Polar Fields</a></td>
    <td><a href="/track/Aurora_Borealis">Aurora Borealis</a></td>
    <td><span>03:45</span></td>
  </tr>
  <tr>
    <td><a href="/track/Dupe_Test">Dupe Test</a></td>
    <td><a href="/track/Dupe_Test">Dupe Test</a></td>
  </tr>
</table>
</body></html>
''';

const String kOverlayHtml = '''
<html><body>
  <div>Test by The Ishihara Test</div>
  <a href="https://creativecommons.org/licenses/by-nc-sa/3.0/">CC BY-NC-SA</a>
  <a href="https://freemusicarchive.org/track/92_Test/download/">Download</a>
</body></html>
''';

Track kFmaTrack() => Track(
      sourceId: 'fma',
      sourceTrackId: '92_Test',
      title: 'Test',
      artist: 'The Ishihara Test',
      durationMs: 488000,
      format: 'mp3',
      addedAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

void main() {
  group('FmaSource.parseSearchHtml', () {
    test('parses track, artist and duration, dedupes repeated anchors',
        () {
      final FmaSource s = FmaSource(
        dio: Dio()..httpClientAdapter = FakeFmaAdapter((_) => _html('')),
        limiter: RateLimiter(Duration.zero),
      );
      final List<FmaSearchHit> hits = s.parseSearchHtml(kSearchHtml);
      expect(hits.length, 2); // third row's duplicate anchor collapses
      expect(hits.first.trackPath, '/track/92_Test');
      expect(hits.first.slug, '92_Test');
      expect(hits.first.title, 'Test');
      expect(hits.first.artist, 'The Ishihara Test');
      expect(hits.first.durationSeconds, 8 * 60 + 8);
      expect(hits.last.title, 'Aurora Borealis');
      expect(hits.last.artist, 'Polar Fields');
      expect(hits.last.durationSeconds, 225);
    });
  });

  group('FmaSource (honest capability contract)', () {
    late FakeFmaAdapter adapter;
    late FmaSource source;

    setUp(() {
      adapter = FakeFmaAdapter((options) {
        if (options.uri.path.endsWith('/downloadOverlay/')) {
          return _html(kOverlayHtml);
        }
        return _html(kSearchHtml);
      });
      source = FmaSource(
        dio: Dio()..httpClientAdapter = adapter,
        limiter: RateLimiter(Duration.zero),
      );
    });

    test('flags: search only — no streaming, no downloads', () {
      expect(source.supportsSearch, isTrue);
      expect(source.supportsStreaming, isFalse);
      expect(source.supportsDownload, isFalse);
    });

    test('search maps rows to tracks', () async {
      final List<Track> hits = await source.search('test');
      expect(hits.length, 2);
      expect(hits.first.sourceId, 'fma');
      expect(hits.first.sourceTrackId, '92_Test');
      expect(hits.first.durationMs, 488000);
    });

    test('resolveStream throws the documented account-wall exception',
        () async {
      await expectLater(
        source.resolveStream(kFmaTrack()),
        throwsA(
          isA<SourceApiException>()
              .having((SourceApiException e) => e.message, 'message',
                  contains('account')),
        ),
      );
    });

    test('download throws the documented account-wall exception',
        () async {
      await expectLater(
        source.download(
          kFmaTrack(),
          targetPath: '/tmp/x.mp3',
          quality: AudioQuality.high,
        ),
        throwsA(isA<SourceApiException>()),
      );
    });

    test('fetchLicenseInfo extracts the CC license url', () async {
      final ({String? licenseUrl, String? licenseName}) info =
          await source.fetchLicenseInfo('92_Test');
      expect(
        info.licenseUrl,
        'https://creativecommons.org/licenses/by-nc-sa/3.0/',
      );
    });

    test('getMetadata reports non-downloadable + license url', () async {
      final Map<String, dynamic> meta = await source.getMetadata('92_Test');
      expect(meta['downloadable'], isFalse);
      expect(meta['licenseUrl'], contains('creativecommons.org'));
    });

    runSourceProviderContract(
      'fma',
      () => FmaSource(
        dio: Dio()..httpClientAdapter = FakeFmaAdapter((options) {
          if (options.uri.path.endsWith('/downloadOverlay/')) {
            return _html(kOverlayHtml);
          }
          return _html(kSearchHtml);
        }),
        limiter: RateLimiter(Duration.zero),
      ),
      streamTrack: kFmaTrack(),
      expectsStreamFailure: true,
    );
  });
}

ResponseBody _html(String body) => ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
