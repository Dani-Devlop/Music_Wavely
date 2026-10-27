import 'dart:convert';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One MusicBrainz artist match (subset of the ws/2 artist object).
///
/// Plain immutable class on purpose (no freezed/codegen): the discovery
/// flow only reads these values, and no equality contract is needed —
/// compare fields explicitly where required.
class MbArtist {
  /// Creates an artist match.
  const MbArtist({
    required this.mbid,
    required this.name,
    this.area,
  });

  /// MusicBrainz artist MBID (UUID) used for release-group lookups.
  final String mbid;

  /// Canonical artist name per MusicBrainz.
  final String name;

  /// Origin/birth area name when present in the response.
  final String? area;
}

/// One MusicBrainz release-group (album-level release).
///
/// Same plain-class policy as [MbArtist]; no equality contract is
/// documented — compare fields explicitly where required.
class MbReleaseGroup {
  /// Creates a release group.
  const MbReleaseGroup({
    required this.id,
    required this.title,
    required this.firstReleaseDate,
    required this.primaryType,
  });

  /// MusicBrainz release-group MBID.
  final String id;

  /// Release-group title.
  final String title;

  /// `first-release-date` as returned by MB (`yyyy-MM-dd` when dated).
  final String firstReleaseDate;

  /// `primary-type` (e.g. `Album`); empty string when absent.
  final String primaryType;
}

/// MusicBrainz ws/2 client (artist search + release-group listing).
///
/// Endpoints (docs/METADATA_SOURCES.md, live-verified):
/// - `GET /ws/2/artist?query=<q>&fmt=json&limit=1`
/// - `GET /ws/2/release-group?artist=<mbid>&type=album&fmt=json&limit=N`
///   `&sort=first-release-date desc` (encodes to the documented `+`)
///
/// MB etiquette: 1 req/s enforced by the default [RateLimiter] and the
/// canonical User-Agent set by [CachingHttpClient]. Bodies are cached
/// for 6 h. Every method returns a [Result] and never throws.
class MusicBrainzClient {
  /// Creates the client; [rateLimiter] defaults to 1 req/s (MB policy).
  MusicBrainzClient({required CachingHttpClient http, RateLimiter? rateLimiter})
      : _http = http,
        _rateLimiter = rateLimiter ?? RateLimiter(const Duration(seconds: 1));

  static const Duration _ttl = Duration(hours: 6);

  final CachingHttpClient _http;
  final RateLimiter _rateLimiter;

  /// Searches one artist by [name]; resolves to `null` when MB returns
  /// no match (a success, not a failure).
  Future<Result<MbArtist?>> searchArtist(String name) async {
    await _rateLimiter.waitTurn();
    final url = Uri.parse('https://musicbrainz.org/ws/2/artist')
        .replace(queryParameters: <String, String>{
      'query': name,
      'fmt': 'json',
      'limit': '1',
    });
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<MbArtist?>.err(failure),
      onSuccess: _parseSearch,
    );
  }

  /// Album-type release groups of [mbid], newest first (server-side
  /// `first-release-date desc` sort).
  ///
  /// When [since] is given, only groups with a `first-release-date` at
  /// or after the cutoff (date granularity, `yyyy-MM-dd` string compare)
  /// are kept; undated entries are dropped because they cannot be
  /// proven "new".
  Future<Result<List<MbReleaseGroup>>> releaseGroups(
    String mbid, {
    DateTime? since,
    int limit = 25,
  }) async {
    await _rateLimiter.waitTurn();
    final url = Uri.parse('https://musicbrainz.org/ws/2/release-group')
        .replace(queryParameters: <String, String>{
      'artist': mbid,
      'type': 'album',
      'fmt': 'json',
      'limit': '$limit',
      'sort': 'first-release-date desc',
    });
    final response = await _http.getJson(url, ttl: _ttl);
    return response.fold(
      onErr: (failure) => Result<List<MbReleaseGroup>>.err(failure),
      onSuccess: (body) => _parseGroups(body, since),
    );
  }

  Result<MbArtist?> _parseSearch(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const Result<MbArtist?>.err(
          Failure.parsing(message: 'Unexpected MusicBrainz search payload'),
        );
      }
      final artists = decoded['artists'];
      if (artists is! List || artists.isEmpty) {
        return const Result<MbArtist?>.success(null);
      }
      final first = artists.first;
      if (first is! Map<String, dynamic>) {
        return const Result<MbArtist?>.success(null);
      }
      final mbid = first['id'];
      if (mbid is! String || mbid.isEmpty) {
        return const Result<MbArtist?>.success(null);
      }
      final name = first['name'];
      final area = first['area'];
      final areaName = area is Map<String, dynamic> ? area['name'] : null;
      return Result<MbArtist?>.success(
        MbArtist(
          mbid: mbid,
          name: name is String ? name : '',
          area: areaName is String ? areaName : null,
        ),
      );
    } on FormatException catch (error) {
      return Result<MbArtist?>.err(
        Failure.parsing(
          message: 'Malformed MusicBrainz response',
          cause: error,
        ),
      );
    }
  }

  Result<List<MbReleaseGroup>> _parseGroups(String body, DateTime? since) {
    final cutoff = since == null ? null : _isoDate(since);
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const Result<List<MbReleaseGroup>>.err(
          Failure.parsing(message: 'Unexpected MusicBrainz payload'),
        );
      }
      final groups = decoded['release-groups'];
      if (groups is! List) {
        return const Result<List<MbReleaseGroup>>.success([]);
      }
      final parsed = <MbReleaseGroup>[
        for (final entry in groups)
          if (entry is Map<String, dynamic>)
            if (_toReleaseGroup(entry, cutoff) case final group?) group,
      ];
      return Result<List<MbReleaseGroup>>.success(parsed);
    } on FormatException catch (error) {
      return Result<List<MbReleaseGroup>>.err(
        Failure.parsing(
          message: 'Malformed MusicBrainz response',
          cause: error,
        ),
      );
    }
  }

  static MbReleaseGroup? _toReleaseGroup(
    Map<String, dynamic> entry,
    String? cutoff,
  ) {
    final id = entry['id'];
    final title = entry['title'];
    final date = entry['first-release-date'];
    if (id is! String || id.isEmpty || title is! String) {
      return null;
    }
    final dateText = date is String ? date : '';
    if (cutoff != null &&
        (dateText.isEmpty || dateText.compareTo(cutoff) < 0)) {
      return null;
    }
    final type = entry['primary-type'];
    return MbReleaseGroup(
      id: id,
      title: title,
      firstReleaseDate: dateText,
      primaryType: type is String ? type : '',
    );
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '-${value.month.toString().padLeft(2, '0')}'
      '-${value.day.toString().padLeft(2, '0')}';
}
