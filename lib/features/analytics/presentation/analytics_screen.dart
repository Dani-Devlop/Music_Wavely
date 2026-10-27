import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/analytics/data/analytics_repository.dart';

/// Everything the screen renders for one period, loaded in one provider so
/// the chips switch feels atomic.
class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.totalListenedMs,
    required this.topTracks,
    required this.topArtists,
    required this.topGenres,
    required this.skipRate,
  });

  /// Sum of listened milliseconds in the window (hero figure).
  final int totalListenedMs;

  /// Most played tracks in the window.
  final List<TopEntry> topTracks;

  /// Most played artists in the window.
  final List<ArtistEntry> topArtists;

  /// Most played genres in the window.
  final List<GenreCount> topGenres;

  /// Skipped-session ratio (see `AnalyticsRepository.getSkipRate`).
  final double skipRate;

  /// Empty when nothing was listened to in the window.
  bool get isEmpty => totalListenedMs <= 0 && topTracks.isEmpty;
}

/// Loads all figures of one period through [analyticsRepositoryProvider].
final analyticsSnapshotProvider =
    FutureProvider.family<AnalyticsSnapshot, AnalyticsPeriod>(
        (ref, period) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return AnalyticsSnapshot(
    totalListenedMs: await repo.getTotalListeningTime(period),
    topTracks: await repo.getTopTracks(period),
    topArtists: await repo.getTopArtists(period),
    topGenres: await repo.getTopGenres(period),
    skipRate: await repo.getSkipRate(period),
  );
});

/// Analytics screen ("Listening insights"): period chips, hero listening
/// time, top tracks, top artists, genre bars and skip rate over the local
/// history.
///
/// Deliberately solid containers (same pattern as the settings
/// `_SectionGroup`): no [GlassCard], no [BackdropFilter] — the list can get
/// long and every glass layer would cost a blur pass.
class AnalyticsScreen extends ConsumerStatefulWidget {
  /// Creates the analytics screen.
  const AnalyticsScreen({super.key});

  /// Route path for the router (registered by the orchestrator).
  static const String route = '/analytics';

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.week;

  Future<void> _refresh() async {
    ref.invalidate(analyticsSnapshotProvider(_period));
    await ref.read(analyticsSnapshotProvider(_period).future);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final async = ref.watch(analyticsSnapshotProvider(_period));
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Analytics',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: <Widget>[
              const SizedBox(height: 120),
              ErrorState(
                message: 'Could not load your stats',
                detail: '$error',
                onRetry: _refresh,
              ),
            ],
          ),
          data: (snapshot) => snapshot.isEmpty
              ? ListView(
                  children: <Widget>[
                    SizedBox(
                      height: 480,
                      child: Center(
                        child: EmptyState(
                          icon: Icons.bar_chart,
                          title: 'Play something to see your stats',
                          subtitle:
                              'Your listening time, top tracks and genres '
                              'appear here once you start playing.',
                        ),
                      ),
                    ),
                  ],
                )
              : _content(colors, snapshot),
        ),
      ),
    );
  }

  Widget _content(WavelySemanticColors colors, AnalyticsSnapshot snapshot) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: <Widget>[
        _periodChips(colors),
        const SizedBox(height: Spacing.md),
        _hero(colors, snapshot.totalListenedMs),
        const SizedBox(height: Spacing.md),
        _skipRatePanel(colors, snapshot.skipRate),
        const SizedBox(height: Spacing.md),
        if (snapshot.topGenres.isNotEmpty) ...<Widget>[
          _genresPanel(colors, snapshot.topGenres),
          const SizedBox(height: Spacing.md),
        ],
        if (snapshot.topArtists.isNotEmpty) ...<Widget>[
          _artistsPanel(colors, snapshot.topArtists),
          const SizedBox(height: Spacing.md),
        ],
        if (snapshot.topTracks.isNotEmpty)
          _topTracksPanel(colors, snapshot.topTracks),
      ],
    );
  }

  Widget _periodChips(WavelySemanticColors colors) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        children: <Widget>[
          for (final period in AnalyticsPeriod.values)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: ChipFilter(
                label: period.label,
                selected: period == _period,
                onSelected: (_) => setState(() => _period = period),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hero(WavelySemanticColors colors, int totalMs) {
    return _Panel(
      colors: colors,
      children: <Widget>[
        Text(
          'Listening time',
          style: WavelyTypography.caption12(color: colors.textSecondary),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          _formatListening(totalMs),
          style: WavelyTypography.display32(color: colors.accentColors.accent),
        ),
      ],
    );
  }

  Widget _skipRatePanel(WavelySemanticColors colors, double skipRate) {
    final percent = (skipRate * 100).round();
    return _Panel(
      colors: colors,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Skip rate',
                style:
                    WavelyTypography.body14Medium(color: colors.textPrimary),
              ),
            ),
            Text(
              '$percent%',
              style:
                  WavelyTypography.body14Medium(color: colors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _genresPanel(WavelySemanticColors colors, List<GenreCount> genres) {
    final accent = colors.accentColors.accent;
    return _Panel(
      colors: colors,
      title: 'Top genres',
      children: <Widget>[
        SizedBox(
          height: 160,
          width: double.infinity,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              barTouchData: const BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) =>
                        _genreLabel(colors, genres, value),
                  ),
                ),
              ),
              barGroups: <BarChartGroupData>[
                for (var i = 0; i < genres.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: genres[i].plays.toDouble(),
                        width: 18,
                        color: accent.withValues(alpha: 0.85),
                        borderRadius: AppRadii.bSm,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _genreLabel(
    WavelySemanticColors colors,
    List<GenreCount> genres,
    double value,
  ) {
    final index = value.toInt();
    if (index < 0 || index >= genres.length) {
      return const SizedBox.shrink();
    }
    final genre = genres[index].genre;
    final short = genre.length > 6 ? '${genre.substring(0, 5)}…' : genre;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Text(
        short,
        style: WavelyTypography.micro10(color: colors.textSecondary),
      ),
    );
  }

  Widget _artistsPanel(
    WavelySemanticColors colors,
    List<ArtistEntry> artists,
  ) {
    return _Panel(
      colors: colors,
      title: 'Top artists',
      children: <Widget>[
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            children: <Widget>[
              for (final entry in artists)
                SizedBox(
                  width: 72,
                  child: Column(
                    children: <Widget>[
                      ArtistCircle(name: entry.artist, radius: 24),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        entry.artist,
                        style: WavelyTypography.micro10(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topTracksPanel(WavelySemanticColors colors, List<TopEntry> entries) {
    return _Panel(
      colors: colors,
      title: 'Top tracks',
      children: <Widget>[
        for (final entry in entries)
          TrackTile(
            track: entry.track,
            trailing: Text(
              '${entry.plays}',
              style: WavelyTypography.caption12(
                color: colors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }

  /// Human listening-time label (`Xh Ym` / `Ym`) — an `h:mm:ss` clock would
  /// be unreadable for week/lifetime totals.
  static String _formatListening(int ms) {
    final hours = ms ~/ Duration.millisecondsPerHour;
    final minutes = (ms % Duration.millisecondsPerHour) ~/
        Duration.millisecondsPerMinute;
    if (hours <= 0) {
      return '${minutes}m';
    }
    return '${hours}h ${minutes}m';
  }
}

/// Solid section container (settings `_SectionGroup` pattern, analytics
/// variant with an optional title).
class _Panel extends StatelessWidget {
  const _Panel({
    required this.colors,
    required this.children,
    this.title,
  });

  final WavelySemanticColors colors;
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: WavelyTypography.title18(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.md),
          ],
          ...children,
        ],
      ),
    );
  }
}
