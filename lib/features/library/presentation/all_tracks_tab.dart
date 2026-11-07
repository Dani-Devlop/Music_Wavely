import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/track_list_tab.dart';

/// Songs tab (Phase 6): every track in the library, paged, with persisted
/// sort memory, a bottom QuickSearchBox and advanced multi-select.
///
/// Kept the historical `AllTracksTab` class name (tests + call sites) while
/// the tab bar label comes from the tab manager ("Songs").
class AllTracksTab extends ConsumerWidget {
  /// Creates the all-tracks (Songs) tab.
  const AllTracksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackListTab(
      tab: LibraryTabId.songs,
      trackKeyPrefix: 'all-track',
      watchPage: (ref, page) {
        // The sort key is resolved during build so a sort change (which
        // resets the list via TrackListTab) re-reads the fresh ordering.
        final orderBy = ref.watch(songsOrderByProvider);
        return ref.watch(sortedTracksPagedProvider((page, orderBy)));
      },
    );
  }
}
