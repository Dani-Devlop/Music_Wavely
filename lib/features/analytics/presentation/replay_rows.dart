// ORCHESTRATOR WIRING — "On Repeat" + "Your Top {year}" rows in the library:
//
// Both rows are self-contained (own providers, own empty-state collapse), so
// inserting them anywhere above the tab bar works without further changes.
//
// 1) Add to the imports of
//    `lib/features/library/presentation/library_screen.dart`:
//
//    import 'package:wavely/features/analytics/presentation/replay_rows.dart';
//
// 2) In `LibraryScreen.build`, inside the SafeArea Column, between the
//    GlassCard header and the TabBar, insert the two rows:
//
//              GlassCard( ... existing header ... ),
//              const OnRepeatRow(),      // <-- insert
//              const TopOfYearRow(),     // <-- insert
//              TabBar( ... existing tabs ... ),
//
// (Both rows render SizedBox.shrink when there is nothing to show, so an
// empty library looks exactly as before.)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/analytics/data/analytics_repository.dart';
// lines_longer_than_80_chars is disabled project-wide; this import path
// cannot be wrapped.
import 'package:wavely/features/analytics/presentation/lifetime_favorites_screen.dart';

/// Tracks played at least 3 times in the last 7 days ("On Repeat").
final onRepeatProvider = FutureProvider<List<Track>>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getOnRepeat();
});

/// Most-played tracks of the current calendar year ("Your Top {year}").
final topOfYearProvider = FutureProvider<List<TopEntry>>((ref) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.getTopOfYear(DateTime.now().year);
});

/// Library row: horizontal scroller of the tracks currently "On Repeat"
/// (>= 3 plays within 7 days). Collapses to nothing when empty.
class OnRepeatRow extends ConsumerWidget {
  /// Creates the row.
  const OnRepeatRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(onRepeatProvider).valueOrNull;
    if (tracks == null || tracks.isEmpty) {
      return const SizedBox.shrink();
    }
    return _TrackRow(title: 'On Repeat', tracks: tracks);
  }
}

/// Library row: most-played tracks of the current year. Collapses to nothing
/// when empty; the header action opens the lifetime favorites screen.
class TopOfYearRow extends ConsumerWidget {
  /// Creates the row.
  const TopOfYearRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(topOfYearProvider).valueOrNull;
    if (entries == null || entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final year = DateTime.now().year;
    return _TrackRow(
      title: 'Your Top $year',
      tracks: <Track>[
        for (final entry in entries) entry.track,
      ],
      onAction: () => context.push(LifetimeFavoritesScreen.route),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.title,
    required this.tracks,
    this.onAction,
  });

  final String title;
  final List<Track> tracks;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: title,
          onAction: onAction,
        ),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            children: <Widget>[
              for (final track in tracks)
                SizedBox(
                  width: 248,
                  child: TrackTile(track: track),
                ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
      ],
    );
  }
}
