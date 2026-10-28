import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One Reddit post from an `/r/<sub>/new` listing (metadata only).
class RedditPost {
  /// Creates a post.
  const RedditPost({
    required this.title,
    required this.permalinkUrl,
    this.createdUtc,
  });

  /// Post title.
  final String title;

  /// Absolute permalink (`https://www.reddit.com` + the `permalink`
  /// path from the API).
  final String permalinkUrl;

  /// `created_utc` as a UTC timestamp; `null` when the API omits it.
  final DateTime? createdUtc;
}

/// Reddit JSON listing client (metadata only).
///
/// IMPORTANT: this sandbox received an HTML bot-page instead of JSON
/// during live verification (docs/METADATA_SOURCES.md). The client
/// therefore VALIDATES the payload shape: a body that does not start
/// with `{` after leading whitespace resolves to
/// `Failure.parsing('reddit blocked (non-JSON response)')` and the UI
/// hides the section. 1 h cache TTL; never throws.
class RedditClient {
  /// Creates the client.
  RedditClient({required CachingHttpClient http}) : _http = http;

  static const Duration _ttl = Duration(hours: 1);

  final CachingHttpClient _http;

  /// Newest posts of [subreddit] (up to [limit]).
  Future<Result<List<RedditPost>>> newPosts({
    String subreddit = 'Music',
    int limit = 20,
  }) async {
    final url = Uri.https(
      'www.reddit.com',
      '/r/$subreddit/new.json',
      <String, String>{'limit': '$limit'},
    );
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<List<RedditPost>>.err(failure),
      onSuccess: _parsePosts,
    );
  }

  Result<List<RedditPost>> _parsePosts(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('{')) {
      return const Result<List<RedditPost>>.err(
        Failure.parsing(message: 'reddit blocked (non-JSON response)'),
      );
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return const Result<List<RedditPost>>.err(
          Failure.parsing(message: 'Unexpected Reddit payload'),
        );
      }
      final data = decoded['data'];
      final children =
          data is Map<String, dynamic> ? data['children'] : null;
      if (children is! List) {
        return const Result<List<RedditPost>>.success([]);
      }
      final posts = <RedditPost>[
        for (final child in children)
          if (child is Map<String, dynamic>)
            if (_toPost(child) case final post?) post,
      ];
      return Result<List<RedditPost>>.success(posts);
    } on FormatException catch (error) {
      return Result<List<RedditPost>>.err(
        Failure.parsing(
          message: 'Malformed Reddit response',
          cause: error,
        ),
      );
    }
  }

  static RedditPost? _toPost(Map<String, dynamic> child) {
    final payload = child['data'];
    if (payload is! Map<String, dynamic>) {
      return null;
    }
    final title = payload['title'];
    final permalink = payload['permalink'];
    if (title is! String || permalink is! String) {
      return null;
    }
    final created = payload['created_utc'];
    return RedditPost(
      title: title,
      permalinkUrl: 'https://www.reddit.com$permalink',
      createdUtc: created is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (created * 1000).round(),
              isUtc: true,
            )
          : null,
    );
  }
}
