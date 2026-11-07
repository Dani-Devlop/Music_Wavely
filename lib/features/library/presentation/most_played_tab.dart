import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/track_list_tab.dart';

/// Most Played tab (Phase 6): tracks ordered by `playCount`, most played
/// first, with sort memory, quick search and multi-select.
class MostPlayedTab extends ConsumerWidget {
  /// Creates the most-played tab.
  const MostPlayedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TrackListTab(
      tab: LibraryTabId.mostPlayed,
      trackKeyPrefix: 'most-track',
      emptyTitle: 'No plays yet',
      emptySubtitle: 'Play something and your top tracks show up here.',
      emptyCtaLabel: '',
      watchPage: (ref, page) => ref.watch(mostPlayedPagedProvider(page)),
    );
  }
}
