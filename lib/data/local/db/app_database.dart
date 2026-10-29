import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'package:wavely/data/local/db/daos/artist_follows_dao.dart';
import 'package:wavely/data/local/db/daos/downloads_dao.dart';
import 'package:wavely/data/local/db/daos/http_cache_dao.dart';
import 'package:wavely/data/local/db/daos/lyrics_dao.dart';
import 'package:wavely/data/local/db/daos/news_dao.dart';
import 'package:wavely/data/local/db/daos/parental_dao.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/sync_outbox_dao.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/data/local/db/migrations/0001_init.dart';
import 'package:wavely/data/local/db/migrations/0002_stage_1_2.dart';
import 'package:wavely/data/local/db/migrations/0003_downloads.dart';
import 'package:wavely/data/local/db/migrations/0004_news.dart';
import 'package:wavely/data/local/db/tables/albums.dart';
import 'package:wavely/data/local/db/tables/artist_follows.dart';
import 'package:wavely/data/local/db/tables/artists.dart';
import 'package:wavely/data/local/db/tables/blocked_words.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/data/local/db/tables/http_cache.dart';
import 'package:wavely/data/local/db/tables/liked_tracks.dart';
import 'package:wavely/data/local/db/tables/lyrics_cache.dart';
import 'package:wavely/data/local/db/tables/news_articles.dart';
import 'package:wavely/data/local/db/tables/playlists.dart';
import 'package:wavely/data/local/db/tables/playlist_items.dart';
import 'package:wavely/data/local/db/tables/plays.dart';
import 'package:wavely/data/local/db/tables/profiles_local.dart';
import 'package:wavely/data/local/db/tables/parental_audit.dart';
import 'package:wavely/data/local/db/tables/sync_outbox.dart';
import 'package:wavely/data/local/db/tables/tracks.dart';

part 'app_database.g.dart';

/// The Wavely local database (SQLite via drift, FTS5-backed full-text
/// search).
///
/// `schemaVersion` 1 creates all base tables plus the external-content FTS5
/// index and its sync triggers (see [Migration0001]); version 2 adds the
/// Stage 1.2 tables (cache/outbox/parental/follows — see [Migration0002]);
/// version 3 adds the Stage 2.1 downloads table (see [Migration0003]);
/// version 4 adds the Stage 2.2 news_articles table (see [Migration0004]).
/// Pass a custom [QueryExecutor]
/// for tests, e.g. `AppDatabase(NativeDatabase.memory())`.
@DriftDatabase(
  tables: [
    Tracks,
    Albums,
    Artists,
    Playlists,
    PlaylistItems,
    LikedTracks,
    Plays,
    LyricsCache,
    HttpCache,
    SyncOutbox,
    BlockedWords,
    ProfilesLocal,
    ParentalAudit,
    ArtistFollows,
    Downloads,
    NewsArticles,
  ],
  daos: [
    TracksDao,
    PlaysDao,
    LyricsDao,
    HttpCacheDao,
    SyncOutboxDao,
    ParentalDao,
    ArtistFollowsDao,
    DownloadsDao,
    NewsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await createFts();
        },
        onUpgrade: (m, from, to) async {
          // FTS5 tables cannot be altered in place; recreate on any upgrade.
          await dropFts();
          await createFts();
          if (from < 2) {
            await Migration0002.run(m, this);
          }
          if (from < 3) {
            // Stage 2.1: downloads table.
            await Migration0003.run(m, this);
          }
          if (from < 4) {
            // Stage 2.2: news_articles table.
            await Migration0004.run(m, this);
          }
        },
        // SQLite ships with foreign-key enforcement OFF per connection;
        // turn it on so ON DELETE CASCADE declarations actually fire.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// (Re)creates the FTS5 virtual table and its three sync triggers.
  Future<void> createFts() => Migration0001.create(this);

  /// Drops the FTS5 table and triggers (used before recreation on upgrade).
  Future<void> dropFts() async {
    await customStatement(
      'DROP TRIGGER IF EXISTS ${Migration0001.triggerInsertName}',
    );
    await customStatement(
      'DROP TRIGGER IF EXISTS ${Migration0001.triggerDeleteName}',
    );
    await customStatement(
      'DROP TRIGGER IF EXISTS ${Migration0001.triggerUpdateName}',
    );
    await customStatement('DROP TABLE IF EXISTS tracks_fts');
  }

  static QueryExecutor _open() => driftDatabase(name: 'wavely');
}
