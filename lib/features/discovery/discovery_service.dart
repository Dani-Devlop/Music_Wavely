import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/daos/artist_follows_dao.dart';
import 'package:wavely/data/local/db/daos/plays_dao.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/remote/metadata_clients/deezer_client.dart';
import 'package:wavely/data/remote/metadata_clients/musicbrainz_client.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One new/old release surfaced by the discovery flow.
class DiscoveryRelease {
  /// Creates a release row.
  const DiscoveryRelease({
    required this.artist,
    required this.title,
    required this.date,
    required this.mbid,
  });

  /// Local artist name the release is attributed to (the followed or
  /// most-played seed, not necessarily the MB canonical name).
  final String artist;

  /// Release-group title.
  final String title;

  /// `first-release-date` as returned by MusicBrainz (`yyyy-MM-dd`).
  final String date;

  /// MusicBrainz MBID used for the lookup.
  final String? mbid;

  /// Parsed [date]; `null` when undated.
  DateTime? get dateValue => DateTime.tryParse(date);
}

/// Discovery aggregations over follows, listening history and the
/// MusicBrainz/Deezer metadata clients (Stage 1.2, B10).
///
/// Contract: every method returns a [Result] and never throws. 6 h cache
/// TTLs live in the clients (shared [CachingHttpClient] over
/// `db.httpCacheDao`), so offline reads resolve to cached bodies while
/// they are fresh and to stale bodies while the device is offline.
///
/// Note on [DiscoveryService] construction: [playsDao] is optional so
/// the four-parameter constructor from the task brief keeps compiling;
/// when absent, top artists are derived from `tracks.play_count`
/// instead of the `plays` history.
class DiscoveryService {
  /// Creates the service; [now] is injectable for the 7-day window.
  DiscoveryService({
    required MusicBrainzClient mb,
    required DeezerClient deezer,
    required ArtistFollowsDao followsDao,
    required TracksDao tracksDao,
    this.playsDao,
    DateTime Function()? now,
  })  : _mb = mb,
        _deezer = deezer,
        _followsDao = followsDao,
        _tracksDao = tracksDao,
        _now = now ?? DateTime.now;

  /// Listening history used for top-artist seeding; see the class doc.
  final PlaysDao? playsDao;

  static const int _seedArtistLimit = 3;
  static const int _followedGraceDays = 30;
  static const int _weeklyWindowDays = 7;
  static const int _topTracksPoolSize = 10;
  static const int _trackScanPoolSize = 200;

  final MusicBrainzClient _mb;
  final DeezerClient _deezer;
  final ArtistFollowsDao _followsDao;
  final TracksDao _tracksDao;
  final DateTime Function() _now;

  /// New releases (last 30 days counted from each `followedAt`) across
  /// the artists the user follows. Follows without an MBID are resolved
  /// through [MusicBrainzClient.searchArtist] first (the resolution is
  /// NOT persisted — the dao has no update API — but the 6 h HTTP cache
  /// keeps repeat calls cheap). A follow whose lookups fail is skipped;
  /// only a storage failure of the follows dao itself produces an error.
  Future<Result<List<DiscoveryRelease>>> getNewFromFollowedArtists() async {
    List<ArtistFollowRow> follows;
    try {
      follows = await _followsDao.all();
    } on Object catch (error) {
      return Result<List<DiscoveryRelease>>.err(
        Failure.storage(
          message: 'Could not read followed artists',
          cause: error,
        ),
      );
    }
    if (follows.isEmpty) {
      return const Result<List<DiscoveryRelease>>.success([]);
    }
    final releases = <DiscoveryRelease>[];
    for (final follow in follows) {
      var mbid = follow.mbid;
      if (mbid == null || mbid.isEmpty) {
        mbid = await _resolveMbid(follow.artistName);
      }
      if (mbid == null || mbid.isEmpty) {
        continue;
      }
      final since = follow.followedAt
          .subtract(const Duration(days: _followedGraceDays));
      final groups = await _mb.releaseGroups(mbid, since: since);
      groups.fold(
        onErr: (_) {
          // Skip this follow; the others still contribute.
        },
        onSuccess: (list) {
          for (final group in list) {
            releases.add(
              DiscoveryRelease(
                artist: follow.artistName,
                title: group.title,
                date: group.firstReleaseDate,
                mbid: mbid,
              ),
            );
          }
        },
      );
    }
    releases.sort(_compareReleases);
    return Result<List<DiscoveryRelease>>.success(releases);
  }

  /// Related-artist recommendations seeded by the user's top 3 artists
  /// (play history via [PlaysDao.topTracks] when available, otherwise
  /// `tracks.play_count`). Per seed: Deezer search → related artists;
  /// results are deduped by (case-folded) name and artists already
  /// followed (or seeded) are excluded. A failing seed is skipped; the
  /// call fails only when EVERY seed fails.
  Future<Result<List<DeezerArtist>>> getBecauseYouListenTo() async {
    final followedNames = await _followedNameSet();
    final seeds = await _topArtistNames();
    if (seeds.isEmpty) {
      return const Result<List<DeezerArtist>>.success([]);
    }
    Failure? lastFailure;
    var anySeedSucceeded = false;
    final collected = <DeezerArtist>[];
    final seen = <String>{
      for (final seed in seeds) seed.trim().toLowerCase(),
    };
    for (final seed in seeds) {
      final search = await _deezer.searchArtist(seed);
      final deezerId = search.fold(
        onErr: (failure) {
          lastFailure = failure;
          return null;
        },
        onSuccess: (artist) => artist?.id,
      );
      if (deezerId == null) {
        continue;
      }
      final related = await _deezer.relatedArtists(deezerId);
      related.fold(
        onErr: (failure) {
          lastFailure = failure;
        },
        onSuccess: (artists) {
          anySeedSucceeded = true;
          for (final artist in artists) {
            final key = artist.name.trim().toLowerCase();
            if (key.isEmpty || seen.contains(key)) {
              continue;
            }
            if (followedNames.contains(key)) {
              continue;
            }
            seen.add(key);
            collected.add(artist);
          }
        },
      );
    }
    if (!anySeedSucceeded) {
      return Result<List<DeezerArtist>>.err(
        lastFailure ??
            const Failure.unknown(message: 'Deezer discovery failed'),
      );
    }
    return Result<List<DeezerArtist>>.success(collected);
  }

  /// "New this week" among the user's top artists.
  ///
  /// HONEST INTERPRETATION: MusicBrainz cannot query release groups by
  /// *genre*, so despite the feature name this section is artist-scoped:
  /// followed artists first (up to 3, stored MBIDs preferred), then
  /// most-played artists to fill the seed budget, keeping only release
  /// groups whose `first-release-date` is within the last 7 days. Genre
  /// data from the local library is intentionally NOT used for the MB
  /// query.
  Future<Result<List<DiscoveryRelease>>> getNewReleasesThisWeek() async {
    final since = _now().subtract(const Duration(days: _weeklyWindowDays));
    final seeds = <String>[
      ...await _followedArtistNames(),
      ...await _topArtistNames(),
    ];
    final unique = <String>[];
    for (final seed in seeds) {
      final key = seed.trim().toLowerCase();
      if (key.isEmpty ||
          unique.any((existing) => existing.trim().toLowerCase() == key)) {
        continue;
      }
      unique.add(seed);
    }
    final picks = unique.take(_seedArtistLimit).toList();
    if (picks.isEmpty) {
      return const Result<List<DiscoveryRelease>>.success([]);
    }
    final releases = <DiscoveryRelease>[];
    Failure? lastFailure;
    var anyLookupSucceeded = false;
    for (final name in picks) {
      final mbid = await _mbidFor(name);
      if (mbid == null || mbid.isEmpty) {
        continue;
      }
      final groups = await _mb.releaseGroups(mbid, since: since);
      groups.fold(
        onErr: (failure) {
          lastFailure = failure;
        },
        onSuccess: (list) {
          anyLookupSucceeded = true;
          for (final group in list) {
            releases.add(
              DiscoveryRelease(
                artist: name,
                title: group.title,
                date: group.firstReleaseDate,
                mbid: mbid,
              ),
            );
          }
        },
      );
    }
    if (!anyLookupSucceeded && lastFailure != null) {
      return Result<List<DiscoveryRelease>>.err(lastFailure!);
    }
    releases.sort(_compareReleases);
    return Result<List<DiscoveryRelease>>.success(releases);
  }

  Future<List<String>> _followedArtistNames() async {
    try {
      final follows = await _followsDao.all();
      return <String>[for (final follow in follows) follow.artistName];
    } on Object catch (_) {
      return const <String>[];
    }
  }

  Future<Set<String>> _followedNameSet() async => <String>{
        for (final name in await _followedArtistNames())
          name.trim().toLowerCase(),
      };

  /// Stored follow MBIDs short-circuit the search round-trip.
  Future<String?> _mbidFor(String artistName) async {
    final key = artistName.trim().toLowerCase();
    try {
      for (final follow in await _followsDao.all()) {
        if (follow.artistName.trim().toLowerCase() == key) {
          final stored = follow.mbid;
          if (stored != null && stored.isNotEmpty) {
            return stored;
          }
        }
      }
    } on Object catch (_) {
      // Fall through to the search below.
    }
    return _resolveMbid(artistName);
  }

  Future<String?> _resolveMbid(String artistName) async {
    final result = await _mb.searchArtist(artistName);
    return result.fold(
      onErr: (_) => null,
      onSuccess: (artist) => artist?.mbid,
    );
  }

  /// Top artist names: play-history play totals when [playsDao] exists
  /// (top 10 tracks weighted by their exact play counts), else the sum of
  /// `playCount` over the first 200 tracks of the library.
  Future<List<String>> _topArtistNames() async {
    final counts = <String, int>{};
    final display = <String, String>{};
    final playsDao = this.playsDao;
    if (playsDao != null) {
      // Weight by real play totals: an artist with 19 plays must outrank
      // one with 6 even when the former owns two tracks of the top pool.
      for (final (track, plays) in await playsDao.topTracksWithCounts(
        limit: _topTracksPoolSize,
      )) {
        _bump(counts, display, track.artist, plays);
      }
    } else {
      for (final track in await _tracksDao.getAll(
        limit: _trackScanPoolSize,
        offset: 0,
      )) {
        if (track.playCount > 0) {
          _bump(counts, display, track.artist, track.playCount);
        }
      }
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byWeight = counts[b]!.compareTo(counts[a]!);
        if (byWeight != 0) {
          return byWeight;
        }
        return a.compareTo(b);
      });
    return <String>[
      for (final key in ranked.take(_seedArtistLimit)) display[key]!,
    ];
  }

  static void _bump(
    Map<String, int> counts,
    Map<String, String> display,
    String rawName,
    int weight,
  ) {
    final name = rawName.trim();
    if (name.isEmpty) {
      return;
    }
    final key = name.toLowerCase();
    counts[key] = (counts[key] ?? 0) + weight;
    display[key] ??= name;
  }

  static int _compareReleases(DiscoveryRelease a, DiscoveryRelease b) {
    final aDate = a.dateValue;
    final bDate = b.dateValue;
    if (aDate == null && bDate == null) {
      return 0;
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    return bDate.compareTo(aDate);
  }
}

/// Builds the discovery chain over the app database's HTTP cache
/// (a [CachingHttpClient] bound to `db.httpCacheDao`, rate-limited
/// clients on top, DAOs straight from the shared [databaseProvider]).
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final db = ref.watch(databaseProvider);
  final http = CachingHttpClient(cacheDao: db.httpCacheDao);
  return DiscoveryService(
    mb: MusicBrainzClient(http: http),
    deezer: DeezerClient(http: http),
    followsDao: db.artistFollowsDao,
    tracksDao: db.tracksDao,
    playsDao: db.playsDao,
  );
});
