import 'package:dio/dio.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;

import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/source_file.dart';
import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/source_exception.dart';

/// One parsed FMA search-result row.
class FmaSearchHit {
  /// Creates a parsed hit.
  const FmaSearchHit({
    required this.trackPath,
    required this.title,
    this.artist = '',
    this.durationSeconds = 0,
  });

  /// Track page path, e.g. `/track/92_Test`.
  final String trackPath;

  /// Track title (anchor text).
  final String title;

  /// Artist display name when the row carried an artist anchor.
  final String artist;

  /// Duration in seconds when the row carried a duration cell.
  final int durationSeconds;

  /// Slug used as [Track.sourceTrackId].
  String get slug => trackPath.replaceFirst(RegExp(r'^/track/'), '');
}

/// Free Music Archive provider.
///
/// Live-verified in the Stage 2.1 session (curl against
/// freemusicarchive.org):
/// - The legacy JSON API (`/api/trackSearch`, `/api/get/tracks.json`) is
///   dead → HTTP 404.
/// - The search page (`/search?quicksearch=...`) answers 200 with parseable
///   `/track/<slug>` anchors, artist anchors, durations and
///   `.../downloadOverlay/` links (license + download anchor inside).
/// - Following the per-track download link redirects to `/login`: FMA gates
///   downloads behind an account. Wavely does not scrape or bypass account
///   walls, so this source is **search + license-metadata only**:
///   `supportsStreaming` / `supportsDownload` are `false` and
///   [resolveStream] / [download] throw [SourceApiException].
///
/// robots.txt: no `User-agent: *` block (specific AI crawlers only);
/// the provider still rate-limits itself to 1 request / 2 s.
class FmaSource implements SourceProvider {
  /// Creates the source; [limiter] defaults to the 1 req / 2 s budget.
  FmaSource({Dio? dio, RateLimiter? limiter})
      : _dio = dio ?? Dio(),
        limiter = limiter ?? RateLimiter(const Duration(seconds: 2));

  final Dio _dio;

  /// Politeness limiter (1 request per 2 seconds).
  final RateLimiter limiter;

  @override
  String get id => sourceId;

  @override
  String get displayName => 'Free Music Archive';

  @override
  bool get supportsStreaming => false;

  @override
  bool get supportsDownload => false;

  @override
  bool get supportsSearch => true;

  /// Source identifier used for FMA-derived tracks.
  static const String sourceId = 'fma';

  /// Site base URL.
  static const String baseUrl = 'https://freemusicarchive.org';

  /// Parses the search-result HTML into rows.
  List<FmaSearchHit> parseSearchHtml(String body) {
    final html.Document doc = html_parser.parse(body);
    final List<FmaSearchHit> hits = <FmaSearchHit>[];
    final Set<String> seen = <String>{};
    for (final html.Element a
        in doc.querySelectorAll('a[href^="/track/"]')) {
      final String href = a.attributes['href'] ?? '';
      final String title = a.text.trim();
      if (href.isEmpty || title.isEmpty || !seen.add(href)) {
        continue;
      }
      // Artist: nearest preceding artist anchor inside the same row container.
      String artist = '';
      int durationSeconds = 0;
      html.Element? row = a.parent;
      while (row != null && row.localName != 'tr' && row.localName != 'li') {
        row = row.parent;
      }
      if (row != null) {
        final html.Element? artistAnchor =
            row.querySelector('a[href^="/artist/"]');
        if (artistAnchor != null) {
          artist = artistAnchor.text.trim();
        }
        final RegExp durationRe = RegExp(r'^\s*(\d+):(\d{2})\s*$');
        for (final html.Element span in row.querySelectorAll('span')) {
          final RegExpMatch? m = durationRe.firstMatch(span.text);
          if (m != null) {
            durationSeconds =
                int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
            break;
          }
        }
      }
      hits.add(
        FmaSearchHit(
          trackPath: href,
          title: title,
          artist: artist,
          durationSeconds: durationSeconds,
        ),
      );
    }
    return hits;
  }

  @override
  Future<List<Track>> search(String q, {int limit = 20}) async {
    if (q.trim().isEmpty) {
      return const <Track>[];
    }
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio.get<dynamic>(
      '$baseUrl/search',
      queryParameters: <String, dynamic>{'quicksearch': q.trim()},
      options: Options(responseType: ResponseType.plain),
    );
    final Object? body = res.data;
    if (body is! String) {
      throw const SourceApiException('fma: non-text search response');
    }
    final DateTime now = DateTime.now().toUtc();
    return parseSearchHtml(body)
        .take(limit)
        .map(
          (FmaSearchHit hit) => Track(
            sourceId: sourceId,
            sourceTrackId: hit.slug,
            title: hit.title,
            artist: hit.artist,
            durationMs: hit.durationSeconds * 1000,
            format: 'mp3',
            explicit: false,
            addedAt: now,
            updatedAt: now,
          ),
        )
        .toList();
  }

  @override
  Future<StreamUrl> resolveStream(Track t) async {
    throw const SourceApiException(
      'fma: streaming is unavailable — Free Music Archive gates audio '
      'downloads behind an account (verified: the per-track download link '
      'redirects to /login). Wavely does not bypass account walls.',
    );
  }

  @override
  Future<dynamic> download(
    Track t, {
    required String targetPath,
    required AudioQuality quality,
  }) async {
    throw const SourceApiException(
      'fma: downloads are unavailable — Free Music Archive gates downloads '
      'behind an account (verified: the per-track download link redirects '
      'to /login). Wavely does not bypass account walls.',
    );
  }

  /// Fetches the download-overlay page for [slug] and returns the license
  /// URL + FMA license name it declares (used for provenance display).
  Future<({String? licenseUrl, String? licenseName})>
      fetchLicenseInfo(String slug) async {
    await limiter.waitTurn();
    final Response<dynamic> res = await _dio.get<dynamic>(
      '$baseUrl/track/$slug/downloadOverlay/',
      options: Options(responseType: ResponseType.plain),
    );
    final Object? body = res.data;
    if (body is! String) {
      throw const SourceApiException('fma: non-text overlay response');
    }
    final html.Document doc = html_parser.parse(body);
    String? licenseUrl;
    for (final html.Element a in doc.querySelectorAll('a[href]')) {
      final String href = a.attributes['href'] ?? '';
      if (href.startsWith('https://creativecommons.org/licenses/')) {
        licenseUrl = href;
        break;
      }
    }
    return (licenseUrl: licenseUrl, licenseName: null);
  }

  @override
  Future<Map<String, dynamic>> getMetadata(String sourceTrackId) async {
    final ({String? licenseUrl, String? licenseName}) license =
        await fetchLicenseInfo(sourceTrackId);
    return <String, dynamic>{
      'sourceTrackId': sourceTrackId,
      'licenseUrl': license.licenseUrl,
      'downloadable': false,
    };
  }
}
