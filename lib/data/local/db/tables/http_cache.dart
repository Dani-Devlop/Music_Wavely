import 'package:drift/drift.dart';

/// HTTP response cache row for metadata clients (Stage 1.2, B1/B10).
///
/// Every metadata client (MusicBrainz, Deezer, Wikipedia, ...) stores its
/// last successful response body here, keyed by a request-URL hash. Offline
/// reads resolve to the cached body until its TTL expires.
@DataClassName('HttpCacheRow', companion: 'HttpCacheCompanion')
class HttpCache extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable request key: sha256 of method + URL (+ sorted query params).
  TextColumn get requestKey => text().unique()();

  /// Raw response body (JSON text).
  TextColumn get body => text()();

  /// HTTP status code of the cached response (2xx bodies only are stored).
  IntColumn get statusCode => integer()();

  /// When the response was stored.
  DateTimeColumn get fetchedAt => dateTime()();

  /// Cache lifetime for this entry; expired entries are refreshed online.
  DateTimeColumn get expiresAt => dateTime()();
}
