import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/sync/sync_backend.dart';

/// Production [SyncBackend] over the Supabase PostgREST API.
///
/// Client call chain (deliberately thin — every mapping step is a pure
/// static function below and unit tested in
/// `test/data/sync/supabase_sync_backend_test.dart` WITHOUT a client):
///
/// - push:  for each row -> `remoteTableFor(row.tableName)`
///          -> normal ops: `client.from(table).upsert(payload)`, or
///             `client.from(table).delete().match(payload)` when
///             `op == 'delete'`
///          -> `track_stats_daily` rows carry a batch payload and expand into
///             one upsert per entry (`client.from(table).upsert(entry)`).
/// - pull:  `client.from('plays').select().gt('started_at', sinceIso)`
///          -> `RemotePlay.fromMap` per row.
/// - pullSettings: `client.from('user_settings').select()`
///          `.order('updated_at')` `.limit(1)` `.maybeSingle()`
///          -> `RemoteSettingsSnapshot`.
///
/// Attribution (user_id) is NOT written by the client: remote tables carry a
/// `user_id` column defaulting to `auth.uid()` guarded by RLS, which also
/// enforces the `(user_id, fingerprint, started_at)` play-dedupe key. The
/// outbox payload therefore never contains a user id.
class SupabaseSyncBackend implements SyncBackend, SettingsPullable {
  /// Binds the backend to an authenticated (or anon) [client].
  SupabaseSyncBackend({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  // -- remote table names ----------------------------------------------------

  /// Remote table for play sessions.
  static const String tablePlays = 'plays';

  /// Remote table for followed artists.
  static const String tableArtistFollows = 'artist_follows';

  /// Remote table for settings rows (LWW via `updated_at`).
  static const String tableUserSettings = 'user_settings';

  /// Remote table for the daily listening aggregates (one batch row per day
  /// is expanded into per-entry upserts).
  static const String tableTrackStatsDaily = 'track_stats_daily';

  /// Maps a local outbox `tableName` to its remote table; null for tables
  /// the backend does not sync (those outbox rows are skipped on push).
  static String? remoteTableFor(String outboxTableName) =>
      switch (outboxTableName) {
        'plays' => tablePlays,
        'artist_follows' => tableArtistFollows,
        'user_settings' => tableUserSettings,
        'track_stats_daily' => tableTrackStatsDaily,
        _ => null,
      };

  // -- pure payload mappers (tested without a client) ------------------------

  /// Canonical payload for one remote `plays` row (snake_case columns).
  static Map<String, dynamic> playToPayload({
    required String fingerprint,
    required String title,
    required String artist,
    String? album,
    required String source,
    required String deviceId,
    required DateTime startedAt,
    required int listenedMs,
    required bool completed,
  }) =>
      <String, dynamic>{
        'fingerprint': fingerprint,
        'title': title,
        'artist': artist,
        'album': album,
        'source': source,
        'device_id': deviceId,
        'started_at': startedAt.toIso8601String(),
        'listened_ms': listenedMs,
        'completed': completed,
      };

  /// Payload of an outbox row keying plays by fingerprint: the rowKey format
  /// is `'<fingerprint>:<startedAtIso>'`; the fingerprint part is forced into
  /// the payload so a corrupted payload can never push a mismatched row.
  static Map<String, dynamic> playPayloadFromRow(SyncOutboxRow row) {
    final payload = jsonDecode(row.payload) as Map<String, dynamic>;
    final fingerprint = fingerprintFromRowKey(row.rowKey);
    if (fingerprint != null) {
      payload['fingerprint'] = fingerprint;
    }
    return payload;
  }

  /// Extracts the fingerprint prefix of a plays rowKey, or null when the
  /// key does not follow the `'<fingerprint>:<startedAtIso>'` format.
  static String? fingerprintFromRowKey(String rowKey) {
    final separator = rowKey.indexOf(':');
    if (separator <= 0) {
      return null;
    }
    final candidate = rowKey.substring(0, separator);
    // sha1 hex digests are exactly 40 lowercase hex chars.
    final isSha1 = candidate.length == 40 &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(candidate);
    return isSha1 ? candidate : null;
  }

  /// Expands a `track_stats_daily` batch payload (`{'day': ..., 'entries':
  /// [{'fingerprint', 'plays', 'listened_ms'}, ...]}`) into one remote row
  /// per entry.
  static List<Map<String, dynamic>> dailyStatsEntriesFromPayload(
    String payload,
  ) {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final day = decoded['day'] as String;
    final entries = decoded['entries'] as List<dynamic>;
    return <Map<String, dynamic>>[
      for (final entry in entries)
        <String, dynamic>{
          'day': day,
          'fingerprint':
              (entry as Map<String, dynamic>)['fingerprint'] as String,
          'plays': (entry['plays'] as num).toInt(),
          'listened_ms': (entry['listened_ms'] as num).toInt(),
        },
    ];
  }

  // -- SyncBackend -----------------------------------------------------------

  @override
  Future<Result<void>> push(List<SyncOutboxRow> batch) async {
    try {
      for (final row in batch) {
        final table = remoteTableFor(row.tableName);
        if (table == null) {
          continue;
        }
        if (table == tableTrackStatsDaily) {
          for (final entry in dailyStatsEntriesFromPayload(row.payload)) {
            await _client.from(table).upsert(entry);
          }
          continue;
        }
        final payload = row.tableName == 'plays'
            ? playPayloadFromRow(row)
            : jsonDecode(row.payload) as Map<String, dynamic>;
        if (row.op == 'delete') {
          await _client.from(table).delete().match(payload);
        } else {
          await _client.from(table).upsert(payload);
        }
      }
      return const Result<void>.success(null);
    } on Exception catch (e) {
      return Result<void>.err(
        Failure.network(message: 'Supabase push failed', cause: e),
      );
    } on Object catch (e) {
      return Result<void>.err(
        Failure.unknown(message: 'Supabase push failed', cause: e),
      );
    }
  }

  @override
  Future<Result<List<RemotePlay>>> pull(DateTime since) async {
    try {
      final rows = await _client
          .from(tablePlays)
          .select()
          .gt('started_at', since.toIso8601String());
      final plays = <RemotePlay>[
        for (final row in rows as List<dynamic>)
          RemotePlay.fromMap(
            Map<String, dynamic>.from(row as Map<dynamic, dynamic>),
          ),
      ];
      return Result<List<RemotePlay>>.success(plays);
    } on Exception catch (e) {
      return Result<List<RemotePlay>>.err(
        Failure.network(message: 'Supabase pull failed', cause: e),
      );
    } on Object catch (e) {
      return Result<List<RemotePlay>>.err(
        Failure.unknown(message: 'Supabase pull failed', cause: e),
      );
    }
  }

  @override
  Future<Result<RemoteSettingsSnapshot?>> pullSettings() async {
    try {
      final row = await _client
          .from(tableUserSettings)
          .select()
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) {
        return const Result<RemoteSettingsSnapshot?>.success(null);
      }
      final map = Map<String, dynamic>.from(row);
      final updatedRaw = map.remove('updated_at');
      return Result<RemoteSettingsSnapshot?>.success(
        RemoteSettingsSnapshot(
          payload: map,
          updatedAt: DateTime.parse(updatedRaw! as String),
        ),
      );
    } on Exception catch (e) {
      return Result<RemoteSettingsSnapshot?>.err(
        Failure.network(message: 'Supabase settings pull failed', cause: e),
      );
    } on Object catch (e) {
      return Result<RemoteSettingsSnapshot?>.err(
        Failure.unknown(message: 'Supabase settings pull failed', cause: e),
      );
    }
  }
}
