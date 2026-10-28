import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/news/data/news_article.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/news/data/news_providers.dart';
import 'package:wavely/features/news/presentation/news_settings_screen.dart';

/// Route of the news screen (registered in the Stage 2.2 router block).
const String newsRoute = '/news';

enum _NewsStatus { loading, ready, empty, error }

/// Music-news feed (Stage 2.2): category chips + article cards over
/// [NewsService]. Tap opens the article in the external browser through
/// the existing [LinkLauncher]; pull-to-refresh re-runs the merge (the
/// 30-minute HTTP cache is honored, mirroring the discovery screen).
class NewsScreen extends ConsumerStatefulWidget {
  /// Creates the news screen.
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  _NewsStatus _status = _NewsStatus.loading;
  List<NewsArticle> _articles = const <NewsArticle>[];
  String? _error;
  late Set<NewsCategory> _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(newsPrefsProvider).selectedOrAll.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _status = _NewsStatus.loading);
    try {
      final NewsService service = await ref.read(newsServiceProvider.future);
      final List<NewsArticle> articles = await service.getArticles(
        categories: _selected.toList(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _articles = articles;
        _status = articles.isEmpty ? _NewsStatus.empty : _NewsStatus.ready;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _NewsStatus.error;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleCategory(NewsCategory category, bool on) async {
    setState(() {
      if (on) {
        _selected.add(category);
      } else {
        _selected.remove(category);
      }
    });
    await ref
        .read(newsPrefsProvider)
        .setSelectedCategories(_selected.toList());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'News',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            key: const Key('news-settings-button'),
            tooltip: 'News settings',
            icon: Icon(Icons.tune_rounded, color: colors.textSecondary),
            onPressed: () => unawaited(context.push(newsSettingsRoute)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              children: <Widget>[
                for (final NewsCategory category in NewsCategory.values)
                  Padding(
                    key: ValueKey<String>('news-chip-${category.storageName}'),
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: Center(
                      child: ChipFilter(
                        label: category.label,
                        selected: _selected.contains(category),
                        onSelected: (bool on) =>
                            unawaited(_toggleCategory(category, on)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: switch (_status) {
                _NewsStatus.loading => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      for (var i = 0; i < 5; i++) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.all(Spacing.lg),
                          child: ShimmerBox(height: 72),
                        ),
                      ],
                    ],
                  ),
                _NewsStatus.error => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      EmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'News is unavailable right now',
                        subtitle: _error,
                      ),
                      _openSettingsCta(context, colors),
                    ],
                  ),
                _NewsStatus.empty => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      EmptyState(
                        icon: Icons.newspaper_rounded,
                        title: 'No articles for the selected categories',
                      ),
                      _openSettingsCta(context, colors),
                    ],
                  ),
                _NewsStatus.ready => ListView.builder(
                    padding: const EdgeInsets.all(Spacing.lg),
                    itemCount: _articles.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _articleCard(context, _articles[index]),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _openSettingsCta(BuildContext context, WavelySemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      child: FilledButton.tonal(
        key: const Key('news-open-settings-cta'),
        onPressed: () => unawaited(context.push(newsSettingsRoute)),
        child: const Text('Open news settings'),
      ),
    );
  }

  Widget _articleCard(BuildContext context, NewsArticle article) {
    final colors = context.wavelyColors;
    final String categories = article.categories
        .map((NewsCategory c) => c.label)
        .join(' · ');
    return Padding(
      key: ValueKey<String>('news-article-${article.dedupeKey}'),
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Material(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        child: ListTile(
          contentPadding: const EdgeInsets.all(Spacing.md),
          onTap: () => unawaited(
            ref.read(linkLauncherProvider).launchExternal(Uri.parse(article.url)),
          ),
          leading: ClipRRect(
            borderRadius: AppRadii.bMd,
            child: SizedBox(
              width: 56,
              height: 56,
              child: article.imageUrl == null
                  ? Icon(
                      Icons.newspaper_rounded,
                      color: colors.textTertiary,
                    )
                  : CachedNetworkImage(
                      imageUrl: article.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => ColoredBox(
                        color: colors.surface,
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.newspaper_rounded,
                        color: colors.textTertiary,
                      ),
                    ),
            ),
          ),
          title: Text(
            article.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WavelyTypography.body14Medium(color: colors.textPrimary),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: Spacing.xs),
              Text(
                '${article.source} · ${relativeTime(article.publishedAt)}',
                style: WavelyTypography.caption12(color: colors.textSecondary),
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: Spacing.xs),
                Text(
                  categories,
                  style: WavelyTypography.caption12(color: colors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Relative-time formatter shared by the news cards (`2m ago`, `3h ago`,
/// `5d ago`, else the short date).
String relativeTime(DateTime timestamp) {
  final Duration delta = DateTime.now().difference(timestamp);
  if (delta.inMinutes < 1) {
    return 'just now';
  }
  if (delta.inMinutes < 60) {
    return '${delta.inMinutes}m ago';
  }
  if (delta.inHours < 24) {
    return '${delta.inHours}h ago';
  }
  if (delta.inDays < 7) {
    return '${delta.inDays}d ago';
  }
  return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-'
      '${timestamp.day.toString().padLeft(2, '0')}';
}
