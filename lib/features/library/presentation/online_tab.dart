import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/track_launcher.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/library/presentation/quick_search_box.dart';
import 'package:wavely/features/library/presentation/selection_controller.dart';
import 'package:wavely/features/library/presentation/track_list_tab.dart';

/// Online tab (Phase 6): non-local (streaming / downloaded) tracks grouped
/// by source, with quick search and multi-select across sections.
class OnlineTab extends ConsumerStatefulWidget {
  /// Creates the online tab.
  const OnlineTab({super.key});

  @override
  ConsumerState<OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends ConsumerState<OnlineTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(onlineSourcesProvider);
    final scope = 'online:${identityHashCode(this)}';
    final selection = ref.watch(selectionControllerProvider(scope));

    return sourcesAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: 6,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: 56),
        ),
      ),
      error: (error, stackTrace) => ErrorState(
        message: 'Could not load online tracks',
        detail: error.toString(),
        onRetry: () => ref.invalidate(onlineSourcesProvider),
      ),
      data: (sources) {
        if (sources.isEmpty) {
          return const EmptyState(
            icon: Icons.explore_outlined,
            title: 'No online tracks yet',
            subtitle:
                'Tracks you stream or download from online sources are '
                'collected here.',
          );
        }
        final sections = <Widget>[];
        final allLoaded = <Track>[];
        for (final source in sources) {
          final tracks =
              ref.watch(onlineTracksProvider(source)).asData?.value ??
                  const <Track>[];
          final visible = <Track>[
            for (final track in tracks)
              if (quickSearchMatches(track.title, _query) ||
                  quickSearchMatches(track.artistOrUnknown, _query) ||
                  quickSearchMatches(track.album, _query))
                track,
          ];
          allLoaded.addAll(tracks);
          if (visible.isEmpty && _query.isNotEmpty) {
            continue;
          }
          sections.add(SectionHeader(title: _sourceLabel(source)));
          sections.add(const SizedBox(height: Spacing.xs));
          for (var i = 0; i < visible.length; i++) {
            final track = visible[i];
            final key = trackKey(track);
            sections.add(
              TrackTile(
                key: ValueKey<String>('online-${track.id ?? key}'),
                track: track,
                showSourceBadge: true,
                selected: selection.selectedIds.contains(key),
                onTap: () {
                  if (selection.selectionMode) {
                    ref
                        .read(selectionControllerProvider(scope).notifier)
                        .toggle(key);
                    return;
                  }
                  unawaited(
                    ref
                        .read(trackLauncherProvider)
                        .playTracks(
                          List<Track>.of(visible),
                          startIndex: i,
                        ),
                  );
                },
                onLongPress: () {
                  ref
                      .read(selectionControllerProvider(scope).notifier)
                      .toggle(key);
                },
              ),
            );
          }
          sections.add(const SizedBox(height: Spacing.md));
        }
        if (_query.isNotEmpty && sections.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            subtitle: 'Nothing matches your filter.',
          );
        }
        return Column(
          children: <Widget>[
            if (selection.selectionMode)
              SelectionBar(
                scope: scope,
                allIds: <String>{
                  for (final track in allLoaded) trackKey(track),
                },
                tracksOf: (id) {
                  for (final track in allLoaded) {
                    if (trackKey(track) == id) {
                      return track;
                    }
                  }
                  return null;
                },
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Spacing.lg),
                children: sections,
              ),
            ),
            QuickSearchBox(
              filterKey:
                  const ValueKey<String>('quick-search-online'),
              hintText: 'Filter Online…',
              onQueryChanged: (query) => setState(() => _query = query),
            ),
          ],
        );
      },
    );
  }

  /// Human label for a source id (`youtube` → YouTube, etc.).
  String _sourceLabel(String sourceId) => switch (sourceId) {
        'youtube' => 'YouTube',
        'jamendo' => 'Jamendo',
        'selfHosted' || 'self_hosted' => 'Self-hosted',
        _ => sourceId,
      };
}
