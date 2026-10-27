import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/domain/entities/entities.dart';

/// Privacy contract (B6): the AI snapshot NEVER leaves the device with
/// anything beyond plain metadata. Deliberately omitted:
/// - `filePath` / `coverPath` / any absolute paths (device layout leak),
/// - bitrate/format/checksums (fingerprinting surface),
/// - play timestamps / listening history (PII),
/// - user identifiers of any kind.
///
/// Only `{t, a, al?, g?, l?, id, d}` per track plus aggregate counts are
/// serialized, compact (no spaces), and capped at [LibrarySnapshot.maxTracks].
abstract final class LibrarySnapshot {
  /// Maximum number of tracks embedded in one snapshot.
  static const int maxTracks = 500;

  /// Column ordering used to pick the snapshot cap: most-played first, then
  /// alphabetical title. Trusted internal literal interpolated by
  /// [TracksDao.getAll] (never user input).
  static const String _orderBy = 'play_count DESC, title COLLATE NOCASE ASC';

  /// Builds the compact JSON snapshot of the current library.
  ///
  /// Shape:
  /// ```json
  /// {"tracks":[{"t":"Title","a":"Artist","al":"Album","g":"Genre",
  ///   "l":"en","id":1,"d":213}],
  ///  "counts":{"totalTracks":505,"artists":42,"genres":["Pop"]}}
  /// ```
  /// `d` is duration in whole seconds. Tracks are capped at [maxTracks],
  /// ordered by play count descending then title ascending; counts are
  /// computed over the FULL library (not the cap).
  static Future<String> build({
    required TracksDao tracksDao,
    int maxTracks = maxTracks,
  }) async {
    // One generous page over the whole table (2^30 rows is far beyond any
    // real library); counting happens in Dart so no new SQL has to be added
    // to the DAO contract.
    final all = await tracksDao.getAll(limit: 1 << 30, offset: 0);
    final genres = <String>{};
    final artists = <String>{};
    for (final track in all) {
      artists.add(track.artistOrUnknown);
      final genre = track.genre;
      if (genre != null && genre.trim().isNotEmpty) {
        genres.add(genre);
      }
    }
    final sorted = [...all]..sort((a, b) {
        final byPlays = b.playCount.compareTo(a.playCount);
        if (byPlays != 0) {
          return byPlays;
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final capped = sorted.take(maxTracks).toList(growable: false);

    return jsonEncode(<String, Object>{
      'tracks': <Object>[
        for (final track in capped)
          <String, Object?>{
            't': track.title,
            'a': track.artistOrUnknown,
            'al': track.album,
            'g': track.genre,
            'l': track.language,
            'id': track.id,
            'd': track.durationMs ~/ 1000,
          },
      ],
      'counts': <String, Object>{
        'totalTracks': all.length,
        'artists': artists.length,
        'genres': genres.toList()..sort(),
      },
    });
  }
}
