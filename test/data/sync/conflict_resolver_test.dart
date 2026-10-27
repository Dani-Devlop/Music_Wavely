// authored, awaiting local run.
//
// Pure-function tests for lib/data/sync/conflict_resolver.dart:
// last-write-wins settings resolution (local newer / remote newer / tie →
// remote / missing local stamp → remote, payload passthrough) and the
// keep-both playlist merge (same id → skip, same name different id →
// '<name> (synced)' case-insensitively, new names imported as-is, rename
// collision give-up).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/sync/conflict_resolver.dart';

PlaylistRef _playlist(String id, String name) =>
    PlaylistRef(id: id, name: name);

void main() {
  group('ConflictResolver.resolveSettings (LWW)', () {
    test('newer local stamp wins and returns the local payload', () {
      final resolution = ConflictResolver.resolveSettings(
        local: <String, dynamic>{'volume': 0.4},
        remote: <String, dynamic>{'volume': 0.9},
        localUpdated: DateTime(2026, 6, 2),
        remoteUpdated: DateTime(2026, 6, 1),
      );

      expect(resolution.winner, SettingsWinner.local);
      expect(resolution.value, <String, dynamic>{'volume': 0.4});
    });

    test('newer remote stamp wins and returns the remote payload', () {
      final resolution = ConflictResolver.resolveSettings(
        local: <String, dynamic>{'volume': 0.4},
        remote: <String, dynamic>{'volume': 0.9},
        localUpdated: DateTime(2026, 6, 1),
        remoteUpdated: DateTime(2026, 6, 2),
      );

      expect(resolution.winner, SettingsWinner.remote);
      expect(resolution.value, <String, dynamic>{'volume': 0.9});
    });

    test('a tie (equal stamps, to the millisecond) goes to REMOTE so two '
        'devices converge', () {
      final resolution = ConflictResolver.resolveSettings(
        local: <String, dynamic>{'k': 'local'},
        remote: <String, dynamic>{'k': 'remote'},
        localUpdated: DateTime(2026, 6, 1, 12, 30, 15, 123),
        remoteUpdated: DateTime(2026, 6, 1, 12, 30, 15, 123),
      );

      expect(resolution.winner, SettingsWinner.remote);
      expect(resolution.value, <String, dynamic>{'k': 'remote'});
    });

    test('a missing local stamp (never written before) loses to remote',
        () {
      final resolution = ConflictResolver.resolveSettings(
        local: <String, dynamic>{},
        remote: <String, dynamic>{'theme': 'dark'},
        localUpdated: null,
        remoteUpdated: DateTime(2020, 1, 1),
      );

      expect(resolution.winner, SettingsWinner.remote);
      expect(resolution.value, <String, dynamic>{'theme': 'dark'});
    });

    test('row-level merge: the winning payload is passed through unmixed',
        () {
      final resolution = ConflictResolver.resolveSettings(
        local: <String, dynamic>{'a': 1, 'b': 2},
        remote: <String, dynamic>{'b': 99, 'c': 3},
        localUpdated: DateTime(2026, 1, 1),
        remoteUpdated: DateTime(2026, 1, 2),
      );

      // No per-key merge — LWW is row-level by design.
      expect(resolution.value, <String, dynamic>{'b': 99, 'c': 3});
    });
  });

  group('ConflictResolver.resolvePlaylists (keep-both)', () {
    test('same id already present locally → skip', () {
      final actions = ConflictResolver.resolvePlaylists(
        local: <PlaylistRef>[_playlist('id-1', 'Road Trip')],
        remote: <PlaylistRef>[_playlist('id-1', 'Road Trip (renamed remote)')],
      );

      expect(actions, hasLength(1));
      final action = actions.single;
      expect(action, isA<SkipPlaylistAction>());
      expect(action.remote.id, 'id-1');
      expect((action as SkipPlaylistAction).reason,
          'same id already present locally');
    });

    test('same name but different id → import renamed with "(synced)" '
        '(case-insensitive comparison)', () {
      final actions = ConflictResolver.resolvePlaylists(
        local: <PlaylistRef>[_playlist('local-1', 'Favorites')],
        remote: <PlaylistRef>[_playlist('remote-1', 'FAVORITES')],
      );

      expect(actions, hasLength(1));
      final action = actions.single as ImportPlaylistAction;
      expect(action.remote.id, 'remote-1');
      expect(action.targetName, 'FAVORITES (synced)');
    });

    test('brand-new remote playlists import under their own name', () {
      final actions = ConflictResolver.resolvePlaylists(
        local: <PlaylistRef>[_playlist('l1', 'Local Mix')],
        remote: <PlaylistRef>[
          _playlist('r1', 'Chill'),
          _playlist('r2', 'Focus'),
        ],
      );

      expect(
        [
          for (final action in actions)
            (action as ImportPlaylistAction).targetName,
        ],
        <String>['Chill', 'Focus'],
      );
    });

    test('two remote playlists with the same name: the first imports '
        'as-is, the second is renamed', () {
      final actions = ConflictResolver.resolvePlaylists(
        local: const <PlaylistRef>[],
        remote: <PlaylistRef>[
          _playlist('r1', 'Mix'),
          _playlist('r2', 'Mix'),
        ],
      );

      expect(
        [
          for (final action in actions)
            (action as ImportPlaylistAction).targetName,
        ],
        <String>['Mix', 'Mix (synced)'],
      );
    });

    test('planned renames also reserve their target names for later '
        'remotes', () {
      final actions = ConflictResolver.resolvePlaylists(
        local: <PlaylistRef>[_playlist('l1', 'Mix')],
        remote: <PlaylistRef>[
          _playlist('r1', 'Mix'), // → 'Mix (synced)'
          _playlist('r2', 'Mix (synced)'), // name now also taken…
          _playlist('r3', 'Fresh'),
        ],
      );

      final names = <String>[
        for (final action in actions)
          switch (action) {
            final ImportPlaylistAction import => import.targetName,
            final SkipPlaylistAction skip => 'skip:${skip.remote.id}',
          },
      ];
      // The rename step gives up on double collisions and imports under
      // 'Mix (synced)' anyway (documented behavior; remote ids still
      // disambiguate downstream).
      expect(names, <String>[
        'Mix (synced)',
        'Mix (synced)',
        'Fresh',
      ]);
    });

    test('nothing is ever deleted: every remote playlist produces an action',
        () {
      final actions = ConflictResolver.resolvePlaylists(
        local: <PlaylistRef>[_playlist('r1', 'Same'), _playlist('l2', 'X')],
        remote: <PlaylistRef>[
          _playlist('r1', 'Same'),
          _playlist('r2', 'Y'),
        ],
      );

      expect(actions, hasLength(2));
      expect(actions.whereType<SkipPlaylistAction>(), hasLength(1));
      expect(actions.whereType<ImportPlaylistAction>(), hasLength(1));
    });
  });
}
