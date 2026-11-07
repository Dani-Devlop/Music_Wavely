import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// Label + icon for each library tab.
class LibraryTabMeta {
  const LibraryTabMeta._(this.label, this.icon);

  /// Display label in the tab bar.
  final String label;

  /// Tab icon (manager sheet).
  final IconData icon;
}

/// Presentation metadata for the nine Phase-6 tabs.
const Map<LibraryTabId, LibraryTabMeta> libraryTabMeta =
    <LibraryTabId, LibraryTabMeta>{
  LibraryTabId.songs: LibraryTabMeta._('Songs', Icons.music_note_rounded),
  LibraryTabId.albums: LibraryTabMeta._('Albums', Icons.album_outlined),
  LibraryTabId.artists: LibraryTabMeta._('Artists', Icons.people_alt_outlined),
  LibraryTabId.genres: LibraryTabMeta._('Genres', Icons.category_outlined),
  LibraryTabId.folders: LibraryTabMeta._('Folders', Icons.folder_outlined),
  LibraryTabId.playlists:
      LibraryTabMeta._('Playlists', Icons.playlist_play_rounded),
  LibraryTabId.recentlyAdded:
      LibraryTabMeta._('Recently Added', Icons.fiber_new_rounded),
  LibraryTabId.mostPlayed:
      LibraryTabMeta._('Most Played', Icons.local_fire_department_outlined),
  LibraryTabId.online: LibraryTabMeta._('Online', Icons.explore_outlined),
};

/// Owns the nine-tab layout (order + hidden), hydrated from the persisted
/// config and persisted back on every mutation.
class LibraryTabsNotifier extends StateNotifier<LibraryTabsConfig> {
  LibraryTabsNotifier(this._store) : super(const LibraryTabsConfig()) {
    _hydrate();
  }

  final LibraryViewConfigStore _store;

  Future<void> _hydrate() async {
    final persisted = await _store.readTabs();
    if (mounted) {
      state = persisted;
    }
  }

  /// Moves the tab at [oldIndex] to [newIndex] (ReorderableListView index
  /// semantics) and persists.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = List<LibraryTabId>.of(state.order);
    if (oldIndex < 0 || oldIndex >= order.length) {
      return;
    }
    var target = newIndex;
    if (oldIndex < target) {
      target -= 1;
    }
    if (target < 0 || target >= order.length || target == oldIndex) {
      return;
    }
    final moved = order.removeAt(oldIndex);
    order.insert(target, moved);
    state = state.copyWith(order: order);
    await _store.writeTabs(state);
  }

  /// Shows or hides [tab] and persists. The last visible tab cannot be
  /// hidden (guarded by [LibraryTabsConfig.copyWith]).
  Future<void> toggleHidden(LibraryTabId tab) async {
    final hidden = {...state.hidden};
    if (!hidden.remove(tab)) {
      hidden.add(tab);
    }
    state = state.copyWith(hidden: hidden);
    await _store.writeTabs(state);
  }

  /// Restores the spec default layout.
  Future<void> resetToDefault() async {
    state = const LibraryTabsConfig();
    await _store.writeTabs(state);
  }
}

/// The library tab layout provider (consumed by the library screen + the
/// tab manager sheet).
final libraryTabsProvider =
    StateNotifierProvider<LibraryTabsNotifier, LibraryTabsConfig>((ref) {
  return LibraryTabsNotifier(ref.watch(libraryViewConfigStoreProvider));
});
