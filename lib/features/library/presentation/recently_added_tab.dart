import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/track_list_tab.dart';

/// Recently Added tab (Phase 6): tracks ordered by `addedAt`, newest first,
/// with sort memory, quick search and multi-select.
class RecentlyAddedTab extends ConsumerWidget {
  /// Creates the recently-added tab.
  const RecentlyAddedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackListTab(
      tab: LibraryTabId.recentlyAdded,
      trackKeyPrefix: 'recent-track',
      emptyTitle: 'Nothing added yet',
      emptySubtitle: 'Tracks you scan or download appear here.',
      emptyCtaLabel: '',
      watchPage: (ref, page) => ref.watch(recentlyAddedPagedProvider(page)),
    );
  }
}
