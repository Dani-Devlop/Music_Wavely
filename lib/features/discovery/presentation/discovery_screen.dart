import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/core/errors/result.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/data/remote/metadata_clients/deezer_client.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/discovery/discovery_service.dart';
import 'package:wavely/features/news/data/news_article.dart';
import 'package:wavely/features/news/data/news_providers.dart';
import 'package:wavely/features/news/presentation/news_screen.dart' show relativeTime;

/// Discovery root screen (Stage 1.2, B10).
///
/// Three sections over [DiscoveryService]: "New from artists you
/// follow", "Because you listen to" and "New this week" (see
/// [DiscoveryService.getNewReleasesThisWeek] for the honest
/// artist-scoped interpretation of the name).
///
/// BackdropFilter budget: sections use the settings-screen-style SOLID
/// container ([_SectionGroup]: surface tint + borderGlass + AppRadii) —
/// deliberately NOT [GlassCard] — so this screen renders ZERO blur
/// layers (AppConstants.maxBackdropFiltersPerScreen is 3).
///
/// Offline behaviour: every section is independent — a failed lookup
/// shows the offline empty state (with the failure message as subtitle)
/// while successful sections keep rendering (cached) data. Pull to
/// refresh re-runs all three lookups through a refresh counter; the 6 h
/// HTTP cache is intentionally honored (offline-first), only the UI
/// state is rebuilt.
class DiscoveryScreen extends ConsumerStatefulWidget {
  /// Creates the discovery screen.
  const DiscoveryScreen({super.key});

  /// Route path for the orchestrator's router wiring.
  static const String route = '/discovery';

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  _Section<List<DiscoveryRelease>> _followed = const _SectionLoading();
  _Section<List<DeezerArtist>> _related = const _SectionLoading();
  _Section<List<DiscoveryRelease>> _weekly = const _SectionLoading();

  /// Stage 2.2: "News for you" — `null` while unavailable (service failed
  /// to build, network down with an empty offline cache, ...) so the
  /// section is omitted entirely instead of rendering an extra empty
  /// state. Deliberately fault-silent: discovery's own sections own the
  /// error surface here.
  List<NewsArticle>? _news;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _followed = const _SectionLoading();
      _related = const _SectionLoading();
      _weekly = const _SectionLoading();
      _news = null;
    });
    final service = ref.read(discoveryServiceProvider);
    final followed = await service.getNewFromFollowedArtists();
    if (!mounted) {
      return;
    }
    setState(() => _followed = _toSection(followed));
    final related = await service.getBecauseYouListenTo();
    if (!mounted) {
      return;
    }
    setState(() => _related = _toSection(related));
    final weekly = await service.getNewReleasesThisWeek();
    if (!mounted) {
      return;
    }
    setState(() => _weekly = _toSection(weekly));
    await _loadNews();
  }

  /// Stage 2.2: loads up to 5 articles for the categories selected in the
  /// news settings. ANY failure leaves `_news == null` and the section is
  /// omitted (never throws into the discovery refresh flow).
  Future<void> _loadNews() async {
    try {
      final service = await ref.read(newsServiceProvider.future);
      final articles = await service.getArticles(
        categories: ref.read(newsPrefsProvider).selectedOrAll,
        limit: 5,
      );
      if (!mounted) {
        return;
      }
      setState(() => _news = articles);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _news = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Discover',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.lg),
          children: <Widget>[
            _DiscoverySection(
              title: 'New from artists you follow',
              child: _sectionBody(
                section: _followed,
                emptyTitle: 'Follow artists to see their new releases',
                row: (release) => _releaseRow(context, release),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            _DiscoverySection(
              title: 'Because you listen to',
              child: _sectionBody(
                section: _related,
                emptyTitle: 'Play some music to get recommendations',
                row: (artist) => _artistRow(context, artist),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            _DiscoverySection(
              title: 'New this week',
              child: _sectionBody(
                section: _weekly,
                emptyTitle: 'No new releases this week',
                row: (release) => _releaseRow(context, release),
              ),
            ),
            // -- Stage 2.2: "News for you" (omitted while unavailable) --
            if (_news != null && _news!.isNotEmpty) ...<Widget>[
              const SizedBox(height: Spacing.lg),
              _DiscoverySection(
                title: 'News for you',
                child: Column(
                  children: <Widget>[
                    for (var i = 0; i < _news!.length; i++) ...<Widget>[
                      if (i > 0)
                        Divider(height: 1, color: colors.borderGlass),
                      _newsRow(context, _news![i]),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionBody<T>({
    required _Section<List<T>> section,
    required String emptyTitle,
    required Widget Function(T item) row,
  }) {
    final colors = context.wavelyColors;
    return switch (section) {
      _SectionLoading<List<T>>() => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: CircularProgressIndicator(
              color: colors.accentColors.accent,
            ),
          ),
        ),
      _SectionFailed<List<T>>(:final message) => _SectionOffline(message),
      _SectionReady<List<T>>(:final items) => items.isEmpty
          ? _SectionEmpty(emptyTitle)
          : Column(
              children: <Widget>[
                for (var i = 0; i < items.length; i++) ...<Widget>[
                  if (i > 0) Divider(height: 1, color: colors.borderGlass),
                  row(items[i]),
                ],
              ],
            ),
    };
  }

  Widget _releaseRow(BuildContext context, DiscoveryRelease release) {
    final colors = context.wavelyColors;
    final subtitle = release.date.isEmpty
        ? release.artist
        : '${release.artist} · ${release.date}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(Icons.album_outlined, color: colors.textSecondary),
      title: Text(
        release.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.body14(color: colors.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.caption12(color: colors.textSecondary),
      ),
    );
  }

  Widget _artistRow(BuildContext context, DeezerArtist artist) {
    final colors = context.wavelyColors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(Icons.person_outline, color: colors.textSecondary),
      title: Text(
        artist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.body14(color: colors.textPrimary),
      ),
      subtitle: Text(
        'Recommended for you',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.caption12(color: colors.textSecondary),
      ),
    );
  }

  /// Stage 2.2: one "News for you" row; tap opens the article externally.
  Widget _newsRow(BuildContext context, NewsArticle article) {
    final colors = context.wavelyColors;
    return ListTile(
      key: ValueKey<String>('discovery-news-${article.dedupeKey}'),
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(Icons.newspaper_rounded, color: colors.textSecondary),
      title: Text(
        article.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.body14(color: colors.textPrimary),
      ),
      subtitle: Text(
        '${article.source} · ${relativeTime(article.publishedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WavelyTypography.caption12(color: colors.textSecondary),
      ),
      onTap: () => unawaited(
        ref
            .read(linkLauncherProvider)
            .launchExternal(Uri.parse(article.url)),
      ),
    );
  }
}

sealed class _Section<T> {
  const _Section();
}

class _SectionLoading<T> extends _Section<T> {
  const _SectionLoading();
}

class _SectionReady<T> extends _Section<T> {
  const _SectionReady(this.items);

  final T items;
}

class _SectionFailed<T> extends _Section<T> {
  const _SectionFailed(this.message);

  final String message;
}

_Section<List<T>> _toSection<T>(Result<List<T>> result) => switch (result) {
      Success<List<T>>(:final value) => _SectionReady<List<T>>(value),
      Err<List<T>>(:final failure) => _SectionFailed<List<T>>(failure.message),
    };

/// Solid, token-styled section container (settings-screen `_SectionGroup`
/// pattern) — a GlassCard replacement that renders NO BackdropFilter.
class _DiscoverySection extends StatelessWidget {
  const _DiscoverySection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
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
        children: <Widget>[
          SectionHeader(title: title),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

class _SectionOffline extends StatelessWidget {
  const _SectionOffline(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.wifi_off_outlined,
      title: 'Offline — showing this section when you\'re back online',
      subtitle: message.isEmpty ? null : message,
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyState(icon: Icons.explore_outlined, title: title);
  }
}
