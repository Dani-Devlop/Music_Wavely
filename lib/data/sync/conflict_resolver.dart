/// Pure conflict-resolution rules for the Stage 1.2 sync engine.
///
/// Both entry points are static and side-effect free so they can be unit
/// tested without any database or network involvement.
/// Winner of a last-write-wins settings merge.
enum SettingsWinner { local, remote }

/// Outcome of [ConflictResolver.resolveSettings].
class UserSettingsResolution {
  const UserSettingsResolution._({required this.winner, required this.value});

  /// Which side won.
  final SettingsWinner winner;

  /// The winning payload (local map or remote map, as given — no merging of
  /// individual keys; LWW is row-level by design).
  final Map<String, dynamic> value;
}

/// Reference to one playlist for the keep-both merge.
class PlaylistRef {
  const PlaylistRef({required this.id, required this.name});

  /// Stable playlist identity (local row id or remote uuid).
  final String id;

  /// Human-readable playlist title.
  final String name;
}

/// What the merger should do with one remote playlist.
sealed class PlaylistMergeAction {
  const PlaylistMergeAction({required this.remote});

  /// The remote playlist the action applies to.
  final PlaylistRef remote;
}

/// Import the remote playlist under [targetName].
final class ImportPlaylistAction extends PlaylistMergeAction {
  const ImportPlaylistAction._({
    required super.remote,
    required this.targetName,
  });

  /// Name to use locally — equals [PlaylistRef.name] unless renamed to keep
  /// both playlists (`'<name> (synced)'`).
  final String targetName;
}

/// The remote playlist already exists locally (same id) — nothing to do.
final class SkipPlaylistAction extends PlaylistMergeAction {
  const SkipPlaylistAction._({required super.remote, required this.reason});

  /// Why the playlist was skipped (for logs / debug surfaces).
  final String reason;
}

/// Conflict rules for the sync engine.
abstract final class ConflictResolver {
  /// Last-write-wins merge for `user_settings`.
  ///
  /// Rule: the side with the newer stamp wins; a tie (equal timestamps, to
  /// the millisecond) goes to REMOTE so that two devices converging on the
  /// same state cannot ping-pong forever; a missing local stamp (never
  /// written before) loses to remote.
  static UserSettingsResolution resolveSettings({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required DateTime? localUpdated,
    required DateTime remoteUpdated,
  }) {
    final localWins =
        localUpdated != null && localUpdated.isAfter(remoteUpdated);
    if (localWins) {
      return UserSettingsResolution._(
        winner: SettingsWinner.local,
        value: local,
      );
    }
    return UserSettingsResolution._(
      winner: SettingsWinner.remote,
      value: remote,
    );
  }

  /// Keep-both merge for playlists.
  ///
  /// Rule: every remote playlist is imported — playlists are user content,
  /// so nothing is deleted or overwritten:
  /// - same id already present locally -> skip (already synced),
  /// - same NAME but different id -> import renamed to `'<name> (synced)'`
  ///   so both survive (name comparison is case-insensitive),
  /// - otherwise -> import under its own name.
  ///
  /// Name uniqueness is checked against the local names AND names already
  /// planned for earlier remote entries; if even `'<name> (synced)'` is
  /// taken the rename step gives up and imports under `'<name> (synced)'`
  /// anyway (remote ids still disambiguate the rows downstream).
  static List<PlaylistMergeAction> resolvePlaylists({
    required List<PlaylistRef> local,
    required List<PlaylistRef> remote,
  }) {
    final takenNames = <String>{
      for (final playlist in local) playlist.name.trim().toLowerCase(),
    };
    final localIds = <String>{for (final playlist in local) playlist.id};
    final actions = <PlaylistMergeAction>[];
    for (final playlist in remote) {
      if (localIds.contains(playlist.id)) {
        actions.add(
          SkipPlaylistAction._(
            remote: playlist,
            reason: 'same id already present locally',
          ),
        );
        continue;
      }
      var targetName = playlist.name;
      final baseName = playlist.name.trim().toLowerCase();
      if (takenNames.contains(baseName)) {
        targetName = '${playlist.name} (synced)';
      }
      takenNames.add(targetName.trim().toLowerCase());
      actions.add(
        ImportPlaylistAction._(remote: playlist, targetName: targetName),
      );
    }
    return actions;
  }
}
