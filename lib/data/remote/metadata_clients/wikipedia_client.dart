import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// Wikipedia page summary (artist bio source for the detail screen).
class WikiSummary {
  /// Creates a summary.
  const WikiSummary({
    required this.title,
    required this.extract,
    this.thumbnailUrl,
  });

  /// Canonical page title.
  final String title;

  /// Plain-text intro extract (first paragraphs).
  final String extract;

  /// Lead-thumbnail URL when the page has one.
  final String? thumbnailUrl;
}

/// Wikipedia REST client (`/api/rest_v1/page/summary/<title>`).
///
/// Polite usage: the canonical User-Agent is set by [CachingHttpClient];
/// 24 h cache TTL. Every call returns a [Result] and never throws.
class WikipediaClient {
  /// Creates the client.
  WikipediaClient({required CachingHttpClient http}) : _http = http;

  static const Duration _ttl = Duration(hours: 24);

  final CachingHttpClient _http;

  /// Summarizes the page [title] (spaces become underscores); resolves
  /// to `null` when the page has no usable summary.
  Future<Result<WikiSummary?>> summary(String title) async {
    final slug = title.trim().replaceAll(' ', '_');
    final url = Uri.https(
      'en.wikipedia.org',
      '/api/rest_v1/page/summary/$slug',
    );
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<WikiSummary?>.err(failure),
      onSuccess: _parseSummary,
    );
  }

  Result<WikiSummary?> _parseSummary(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const Result<WikiSummary?>.err(
          Failure.parsing(message: 'Unexpected Wikipedia payload'),
        );
      }
      final pageTitle = decoded['title'];
      final extract = decoded['extract'];
      if (pageTitle is! String || extract is! String) {
        return const Result<WikiSummary?>.success(null);
      }
      final thumbnail = decoded['thumbnail'];
      final source =
          thumbnail is Map<String, dynamic> ? thumbnail['source'] : null;
      return Result<WikiSummary?>.success(
        WikiSummary(
          title: pageTitle,
          extract: extract,
          thumbnailUrl: source is String ? source : null,
        ),
      );
    } on FormatException catch (error) {
      return Result<WikiSummary?>.err(
        Failure.parsing(
          message: 'Malformed Wikipedia response',
          cause: error,
        ),
      );
    }
  }
}
