import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/library_tab_manager.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/selection_controller.dart';
import 'package:wavely/features/library/presentation/sort_menu.dart';

/// Vertical distance (logical px) at which the next page starts loading.
const double _loadMoreThreshold = 400;

/// Height of the placeholder rows shown while the first page loads.
const double _shimmerRowHeight = 56;

/// Number of placeholder rows shown while the first page loads.
const int _shimmerRowCount = 8;

/// Stable selection key for a track (id is nullable for non-local rows).
String trackKey(Track track) =>
    '${track.sourceId}:${track.sourceTrackId}';

/// Watches one paged result for the host tab (reactive — a provider
/// invalidation, e.g. after a scan or a delete, refreshes the list).
typedef TrackPageWatcher = AsyncValue<List<Track>> Function(
  WidgetRef ref,
  int page,
);

/// Generic paged track list shared by the Songs / Recently Added / Most
/// Played tabs (Phase 6): sort menu with memory, bottom QuickSearchBox and
/// advanced multi-select (long-press, Select All / Invert, Play, Play Next,
/// Add to Queue, Add to Playlist, Delete, Share).
///
/// Pages are watched (not cached locally), so the list stays reactive to
/// library invalidations.
class TrackListTab extends ConsumerStatefulWidget {
  /// Creates the track list; [watchPage] loads one page and [tab] drives
  /// the persisted sort memory + selection scope.
  const TrackListTab({
    required this.tab,
    required this.watchPage,
    this.trackKeyPrefix = 'list-track',
    this.emptyTitle = 'No music yet',
    this.emptySubtitle =
        'Add a folder in the Folders tab to start scanning.',
    this.emptyCtaLabel = 'Open Folders',
    super.key,
  });

  /// Library tab this list belongs to (sort memory + selection scope).
  final LibraryTabId tab;

  /// Reactive page watcher (already visibility-filtered by the providers).
  final TrackPageWatcher watchPage;

  /// Prefix for the per-row ValueKeys (kept stable for tests).
  final String trackKeyPrefix;

  /// Empty-state copy (empty [emptyCtaLabel] hides the CTA).
  final String emptyTitle;
  final String emptySubtitle;
  final String emptyCtaLabel;

  @override
  ConsumerState<TrackListTab> createState() => _TrackListTabState();
}

class _TrackListTabState extends ConsumerState<TrackListTab> {
  int _loadedPages = 1;
  bool _canLoadMore = true;
  String _query = '';
  SortKey? _lastSort;

  /// Selection + sort scopes are namespaced per state identity so two lists
  /// never collide.
  String get scopeKey =>
      '${identityHashCode(this)}:${widget.tab.name}';

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _loadMoreThreshold &&
        _canLoadMore) {
      setState(() => _loadedPages++);
    }
    return false;
  }

  /// The loaded pages concatenated, then filtered by the quick search query
  /// (title / artist / album, case-folded contains).
  List<Track> _visibleTracks(List<Track> loaded) => <Track>[
        for (final track in loaded)
          if (quickSearchMatches(track.title, _query) ||
              quickSearchMatches(track.artistOrUnknown, _query) ||
              quickSearchMatches(track.album, _query))
            track,
      ];

  Map<String, Track> _tracksByKey(List<Track> loaded) => <String, Track>{
        for (final track in loaded) trackKey(track): track,
      };

  @override
  Widget build(BuildContext context) {
    // Watch the tab's persisted sort; a change resets the paged list.
    final sort = ref.watch(sortConfigProvider(widget.tab));
    if (_lastSort == null) {
      _lastSort = sort;
    } else if (_lastSort != sort) {
      _lastSort = sort;
      _loadedPages = 1;
      _canLoadMore = true;
    }

    final pages = <AsyncValue<List<Track>>>[
      for (var page = 0; page < _loadedPages; page++)
        widget.watchPage(ref, page),
    ];

    final selection = ref.watch(selectionControllerProvider(scopeKey));
    final showSelection = selection.selectionMode;

    // Loading state: first page still resolving.
    if (pages.first.isLoading && pages.first.asData == null) {
      return ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _shimmerRowCount,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: _shimmerRowHeight),
        ),
      );
    }
    final firstError = pages.firstWhere(
      (page) => page.hasError,
      orElse: () => pages.first,
    );
    if (firstError.hasError && pages.first.asData == null) {
      return ErrorState(
        message: 'Could not load your library',
        detail: firstError.asError?.error.toString(),
        onRetry: () {
          ref.invalidate(sortedTracksPagedProvider);
          setState(() => _loadedPages = 1);
        },
      );
    }

    final loaded = <Track>[
      for (final page in pages)
        if (page.asData case final data?) ...data.value,
    ];
    // A short (or empty) page means there is nothing more to load.
    final lastComplete = pages.last.asData?.value;
    _canLoadMore = lastComplete != null &&
        lastComplete.length == AppConstants.scrollPageSize;
    final visible = _visibleTracks(loaded);
    final tracksByKey = _tracksByKey(loaded);

    return Column(
      children: <Widget>[
        if (showSelection)
          SelectionBar(
            scope: scopeKey,
            allIds: <String>{for (final track in loaded) trackKey(track)},
            tracksOf: (id) => tracksByKey[id],
          ),
        Expanded(
          child: _buildList(loaded, visible, selection),
        ),
        QuickSearchBox(
          filterKey: ValueKey<String>('quick-search-${widget.tab.name}'),
          hintText: 'Filter ${libraryTabMeta[widget.tab]?.label ?? ''}…',
          onQueryChanged: (query) => setState(() => _query = query),
        ),
      ],
    );
  }

  Widget _buildList(
    List<Track> loaded,
    List<Track> visible,
    SelectionState selection,
  ) {
    if (loaded.isEmpty) {
      return EmptyState(
        icon: Icons.library_music,
        title: widget.emptyTitle,
        subtitle: widget.emptySubtitle,
        ctaLabel: widget.emptyCtaLabel.isEmpty ? null : widget.emptyCtaLabel,
        onCta: widget.emptyCtaLabel.isEmpty ? null : _openFoldersTab,
      );
    }
    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No matches',
        subtitle: 'Nothing matches your filter.',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        itemCount: visible.length + (_canLoadMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= visible.length) {
            return const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final track = visible[index];
          final key = trackKey(track);
          final selected = selection.selectedIds.contains(key);
          return TrackTile(
            key:
                ValueKey<String>('${widget.trackKeyPrefix}-${track.id ?? key}'),
            track: track,
            showSourceBadge: true,
            selected: selected,
            onTap: () {
              if (selection.selectionMode) {
                ref
                    .read(selectionControllerProvider(scopeKey).notifier)
                    .toggle(key);
                return;
              }
              unawaited(
                ref
                    .read(trackLauncherProvider)
                    .playTracks(List<Track>.of(visible), startIndex: index),
              );
            },
            onLongPress: () {
              ref
                  .read(selectionControllerProvider(scopeKey).notifier)
                  .toggle(key);
            },
          );
        },
      ),
    );
  }

  void _openFoldersTab() {
    final controller = DefaultTabController.maybeOf(context);
    if (controller != null) {
      final tabs = ref.read(libraryTabsProvider).visibleTabs;
      final foldersIndex = tabs.indexOf(LibraryTabId.folders);
      controller.animateTo(foldersIndex < 0 ? 0 : foldersIndex);
    }
  }
}
