import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/http_cache.dart';

part 'http_cache_dao.g.dart';

/// Cache store behind the metadata clients' offline-first reads.
@DriftAccessor(tables: [HttpCache])
class HttpCacheDao extends DatabaseAccessor<AppDatabase>
    with _$HttpCacheDaoMixin {
  HttpCacheDao(super.attachedDatabase);

  /// Builds the deterministic request key for [method] + [url].
  static String requestKey(String method, String url) =>
      crypto.sha256.convert('$method $url'.codeUnits).toString();

  /// Returns the cached body when present AND not expired; expired rows are
  /// returned as null (and pruned lazily).
  Future<String?> get(String requestKey) async {
    final row = await (select(httpCache)
          ..where((r) => r.requestKey.equals(requestKey)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    if (row.expiresAt.isBefore(DateTime.now())) {
      return null;
    }
    return row.body;
  }

  /// Stores (or overwrites) a response under [requestKey].
  Future<void> put({
    required String requestKey,
    required String body,
    required int statusCode,
    required DateTime expiresAt,
  }) =>
      into(httpCache).insertOnConflictUpdate(
        HttpCacheCompanion.insert(
          requestKey: requestKey,
          body: body,
          statusCode: statusCode,
          fetchedAt: DateTime.now(),
          expiresAt: expiresAt,
        ),
      );

  /// Deletes expired rows; called opportunistically by clients.
  Future<int> prune() => (delete(httpCache)
        ..where((r) => r.expiresAt.isSmallerThanValue(DateTime.now())))
      .go();
}
