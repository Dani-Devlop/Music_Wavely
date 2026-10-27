// ORCHESTRATOR WIRING — the exact snippet to add to
// lib/features/library/presentation/artist_detail_screen.dart (this file
// must NOT be edited by BW1-a; the orchestrator integrates it):
//
//     import 'dart:async';
//     import 'package:wavely/features/discovery/follow_artist.dart';
//
// and inside the header Row of ArtistDetailScreen, after the play-all
// IconButton (3 lines):
//
//     final following = ref.watch(artistFollowStateProvider(artistName));
//     IconButton(
//       icon: Icon(following ? Icons.favorite : Icons.favorite_border),
//       tooltip: following ? 'Unfollow artist' : 'Follow artist',
//       onPressed: () => unawaited(toggleFollow(ref, artistName)),
//     ),
//
// (the `final following` line goes before the IconButton in the Row's
// children list; `unawaited` is already imported there).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/data/local/db/database_provider.dart';

/// Follow state of one artist (by exact dao key, i.e. the artist name
/// as shown on the detail screen).
///
/// Family keyed by artist name; invalidated by [toggleFollow] after a
/// successful toggle so open screens re-read the dao.
final artistFollowStateProvider =
    FutureProvider.family<bool, String>((ref, artistName) async {
  final db = ref.watch(databaseProvider);
  return db.artistFollowsDao.isFollowing(artistName);
});

/// Follows [artistName] when not yet followed, unfollows otherwise
/// ([mbid] is stored on the fresh follow so discovery can skip the
/// MusicBrainz resolution).
///
/// Never throws: a failed toggle leaves the dao untouched and the
/// button state simply re-reads on the next rebuild.
Future<void> toggleFollow(
  WidgetRef ref,
  String artistName, {
  String? mbid,
}) async {
  try {
    final dao = ref.read(databaseProvider).artistFollowsDao;
    if (await dao.isFollowing(artistName)) {
      await dao.unfollow(artistName);
    } else {
      await dao.follow(artistName, mbid: mbid);
    }
    ref.invalidate(artistFollowStateProvider(artistName));
  } on Object catch (_) {
    // Follow/unfollow must never crash the caller.
  }
}
