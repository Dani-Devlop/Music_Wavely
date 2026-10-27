import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Grouped local search results for one query.
class SearchResults {
  /// Empty result set (used for blank queries and "nothing found").
  const SearchResults({
    this.tracks = const <Track>[],
    this.artists = const <Artist>[],
    this.albums = const <Album>[],
  });

  /// Matching tracks (FTS-ranked, capped at the FTS page size).
  final List<Track> tracks;

  /// Matching artists (derived from matches + case-insensitive name filter).
  final List<Artist> artists;

  /// Matching albums (derived from matches + case-insensitive name filter).
  final List<Album> albums;

  /// True when no group contains a result.
  bool get isEmpty => tracks.isEmpty && artists.isEmpty && albums.isEmpty;
}

/// Local library search backed by the FTS5 index.
///
/// Track matches come from `TracksDao.searchFts` (full-text over
/// title/artist/album, prefix-matching the last token). Artist and album
/// groups are derived client-side from the matched tracks AND complemented
/// by a case-insensitive `contains` filter over all known artists/albums, so
/// a match inside e.g. an album name still surfaces that album even when no
/// single track matched the FTS query strongly.
class SearchLocal {
  /// Creates the search usecase over the tracks DAO.
  SearchLocal(this._tracksDao);

  final TracksDao _tracksDao;

  /// Runs the search; blank queries yield an empty result set.
  Future<SearchResults> call(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const SearchResults();
    }
    final matchedTracks = await _tracksDao.searchFts(trimmed);

    final artists = <String, Artist>{};
    final albums = <String, Album>{};
    void collect(List<Track> tracks) {
      for (final track in tracks) {
        final artistName = track.artistOrUnknown;
        artists.putIfAbsent(
          artistName.toLowerCase(),
          () => Artist(
            name: artistName,
            trackCount: 0,
            albumCount: 0,
          ),
        );
        final album = track.album;
        if (album != null) {
          final key = '${artistName.toLowerCase()}::${album.toLowerCase()}';
          albums.putIfAbsent(
            key,
            () => Album(
              key: key,
              title: album,
              artist: artistName,
              trackCount: 0,
              addedAt: track.addedAt,
            ),
          );
        }
      }
    }

    collect(matchedTracks);

    final needle = trimmed.toLowerCase();
    for (final artist in await _tracksDao.distinctArtists()) {
      if (artist.name.toLowerCase().contains(needle)) {
        artists.putIfAbsent(artist.name.toLowerCase(), () => artist);
      }
    }
    for (final album in await _tracksDao.distinctAlbums()) {
      final matches =
          album.title.toLowerCase().contains(needle) ||
              album.artist.toLowerCase().contains(needle);
      if (matches) {
        albums.putIfAbsent(album.key, () => album);
      }
    }

    return SearchResults(
      tracks: matchedTracks,
      artists: artists.values.toList(growable: false),
      albums: albums.values.toList(growable: false),
    );
  }
}
