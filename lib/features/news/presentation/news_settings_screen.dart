import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/news/data/news_category.dart';
import 'package:wavely/features/news/data/news_providers.dart';

/// Route of the news settings screen (nested under [newsRoute]).
const String newsSettingsRoute = '/news/settings';

/// News settings (Stage 2.2): category toggles, custom RSS feeds
/// (validated http/https only) and muted sources.
class NewsSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the news settings screen.
  const NewsSettingsScreen({super.key});

  @override
  ConsumerState<NewsSettingsScreen> createState() =>
      _NewsSettingsScreenState();
}

class _NewsSettingsScreenState extends ConsumerState<NewsSettingsScreen> {
  late Set<String> _selectedNames;
  late List<String> _customRss;
  late List<String> _muted;
  final TextEditingController _rssController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final NewsPrefs prefs = ref.read(newsPrefsProvider);
    _selectedNames = prefs.selectedCategories.toSet();
    _customRss = List<String>.of(prefs.customRss);
    _muted = List<String>.of(prefs.mutedSources);
  }

  @override
  void dispose() {
    _rssController.dispose();
    super.dispose();
  }

  Future<void> _toggleCategory(NewsCategory category, bool on) async {
    setState(() {
      if (on) {
        _selectedNames.add(category.storageName);
      } else {
        _selectedNames.remove(category.storageName);
      }
    });
    await ref
        .read(newsPrefsProvider)
        .setSelectedCategories(
          _selectedNames
              .map(NewsCategory.tryParse)
              .whereType<NewsCategory>()
              .toList(),
        );
  }

  Future<void> _addRss() async {
    final String raw = _rssController.text.trim();
    final String? error = validateRssUrl(raw);
    if (!mounted) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _customRss.add(raw);
      _rssController.clear();
    });
    await ref.read(newsPrefsProvider).setCustomRss(_customRss);
  }

  Future<void> _removeRss(String url) async {
    setState(() => _customRss.remove(url));
    await ref.read(newsPrefsProvider).setCustomRss(_customRss);
  }

  Future<void> _unmute(String source) async {
    setState(() => _muted.remove(source));
    await ref.read(newsPrefsProvider).setMutedSources(_muted);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'News settings',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: <Widget>[
          _Group(
            title: 'Categories',
            children: <Widget>[
              for (final NewsCategory category in NewsCategory.values)
                SwitchListTile(
                  key: ValueKey<String>(
                    'news-toggle-${category.storageName}',
                  ),
                  contentPadding: EdgeInsets.zero,
                  title: Text(category.label),
                  value: _selectedNames.contains(category.storageName),
                  onChanged: (bool on) =>
                      unawaited(_toggleCategory(category, on)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _Group(
            title: 'Custom RSS feeds',
            children: <Widget>[
              TextFormField(
                key: const Key('news-rss-field'),
                controller: _rssController,
                decoration: const InputDecoration(
                  labelText: 'Feed URL',
                  hintText: 'https://example.com/feed.xml',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: Spacing.sm),
              FilledButton.tonalIcon(
                key: const Key('news-rss-add'),
                onPressed: () => unawaited(_addRss()),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('Add feed'),
              ),
              for (final String url in _customRss)
                ListTile(
                  key: ValueKey<String>('news-rss-$url'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.rss_feed_rounded,
                    color: colors.textSecondary,
                  ),
                  title: Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove feed',
                    onPressed: () => unawaited(_removeRss(url)),
                    icon: Icon(Icons.delete_outline, color: colors.textTertiary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _Group(
            title: 'Muted sources',
            children: <Widget>[
              if (_muted.isEmpty)
                Text(
                  'No muted sources.',
                  style: WavelyTypography.caption12(color: colors.textTertiary),
                )
              else
                for (final String source in _muted)
                  ListTile(
                    key: ValueKey<String>('news-muted-$source'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.volume_off_rounded,
                      color: colors.textSecondary,
                    ),
                    title: Text(source),
                    trailing: TextButton(
                      onPressed: () => unawaited(_unmute(source)),
                      child: const Text('Unmute'),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Validates a user-entered RSS URL: must parse as an absolute http(s) URL.
/// Returns the error message, or `null` when valid.
String? validateRssUrl(String raw) {
  if (raw.isEmpty) {
    return 'Enter a feed URL first.';
  }
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'That does not look like a valid URL.';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'Only http(s) feed URLs are supported.';
  }
  return null;
}

/// Reused solid section group (settings `_SectionGroup` pattern).
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
          Text(
            title,
            style: WavelyTypography.title18(color: colors.textPrimary),
          ),
          const SizedBox(height: Spacing.md),
          ...children,
        ],
      ),
    );
  }
}
