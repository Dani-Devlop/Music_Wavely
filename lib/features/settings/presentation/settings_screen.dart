import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wavely/app/app_providers.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/utils/link_launcher.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/analytics/presentation/analytics_screen.dart';
import 'package:wavely/features/downloads/presentation/download_settings_screen.dart';
import 'package:wavely/features/downloads/presentation/downloads_screen.dart';
import 'package:wavely/features/news/presentation/news_screen.dart';
import 'package:wavely/features/auth/presentation/welcome_screen.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';
import 'package:wavely/features/settings/data/cache_cleaner.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/data/update_providers.dart';
import 'package:wavely/features/settings/domain/settings.dart';
import 'package:wavely/features/settings/presentation/screens/audio_settings_screen.dart'
    show kAudioSettingsRoute;
import 'package:wavely/features/settings/presentation/screens/update_screen.dart';
import 'package:wavely/features/settings/presentation/widgets/sources_settings_section.dart';
import 'package:wavely/features/player/presentation/musicolet_dialogs.dart';

/// Bytes per megabyte for the cache-size row (data math, not a token).
const int _bytesPerMb = 1024 * 1024;

/// Diameter of the accent swatch dots in the accent selector.
const double _accentSwatchSize = 12;

/// Project repository URL (shown in the About section; no url_launcher in
/// Stage 1.1 — see _openGitHub).
const String _gitHubUrl = 'https://github.com/Dani-Devlop/Music_Wavely';

/// Presentation-local cache size (manual [FutureProvider], consistent with
/// the Stage 1.1 provider inventory; codegen is reserved for the
/// owner-specced settings/app providers). Invalidated after a cache clear.
final cacheSizeProvider = FutureProvider<int>((ref) => appCacheSizeBytes());

/// One searchable row inside a settings category.
class _SettingsRow {
  const _SettingsRow(this.searchText, this.widget);

  /// Lower-cased text matched against the tree search query (row title,
  /// subtitle and any auxiliary keywords).
  final String searchText;

  final Widget widget;
}

/// One expandable Musicolet-style settings category.
class _SettingsCategory {
  const _SettingsCategory(
    this.title,
    this.icon,
    this.rows, {
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<_SettingsRow> rows;

  /// Categories the tree starts with open (first-run discoverability).
  final bool initiallyExpanded;
}

/// Settings root screen — the deep Musicolet-style tree.
///
/// v1.0.1-beta3 owner spec: a search bar at the top and expandable
/// categories (Language, Interface, Audio, Song Library & Tags, Headset /
/// Bluetooth & Speakers, Notifications, HomeScreen Widgets, Lock Screen,
/// Advanced, Backup & Restore, About). Every row maps onto a REAL,
/// shipped feature — nothing in the tree is a dead switch.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  /// Route path for Task 4's router.
  static const String route = '/settings';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    // Stage 7: one-shot background check; drives the row subtitle + dot.
    // Hermetic under flutter test (the provider short-circuits there).
    final bool updateBadge =
        ref.watch(updateAvailableBadgeProvider).value ?? false;
    final categories = _buildCategories(settings, notifier, updateBadge);
    final searching = _query.isNotEmpty;
    final visibleCategories = searching
        ? categories
            .map(
              (category) => _SettingsCategory(
                category.title,
                category.icon,
                category.rows
                    .where((row) => row.searchText.contains(_query))
                    .toList(growable: false),
                initiallyExpanded: true,
              ),
            )
            .where((category) => category.rows.isNotEmpty)
            .toList(growable: false)
        : categories;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Settings',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        // Musicolet parity: the tree search lives behind a top-right icon
        // (it focuses the always-present search bar below).
        actions: <Widget>[
          IconButton(
            key: const Key('settings-search-icon'),
            tooltip: 'Search settings',
            icon: Icon(Icons.search_rounded, color: colors.textPrimary),
            onPressed: _focusSearch,
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Musicolet-parity: the settings tree has its own search bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.xs,
            ),
            child: TextField(
              key: const Key('settings-search-field'),
              focusNode: _searchFocus,
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search settings…',
                prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, color: colors.textTertiary),
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: visibleCategories.isEmpty
                ? Center(
                    child: Text(
                      'No settings match "$_query"',
                      style: WavelyTypography.body14(
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                : ListView(
                    // Generous cacheExtent: the first test viewport must
                    // find the Interface category without scrolling.
                    cacheExtent: 2000,
                    padding: const EdgeInsets.all(Spacing.lg),
                    children: <Widget>[
                      for (final category in visibleCategories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Spacing.md),
                          child: _CategoryCard(
                            category: category,
                            searching: searching,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // -- category graph -------------------------------------------------------

  /// Every category and row of the tree. Rows pair a search string with
  /// the real, wired widget — the tree is data-driven so the search bar
  /// can filter without special cases.
  List<_SettingsCategory> _buildCategories(
    AppSettings settings,
    SettingsNotifier notifier,
    bool updateBadge,
  ) {
    final colors = context.wavelyColors;
    return <_SettingsCategory>[
      // ── Language ──────────────────────────────────────────────────────
      _SettingsCategory(
        'Language',
        Icons.language_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'language english persian farsi locale rtl فارسی system',
            Semantics(
              label: 'Language',
              child: ListTile(
                key: const ValueKey<String>('settings-language'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'App language',
                  style: WavelyTypography.body14(color: colors.textPrimary),
                ),
                subtitle: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'system',
                      label: Text('System'),
                    ),
                    ButtonSegment<String>(
                      value: 'en',
                      label: Text('EN'),
                    ),
                    ButtonSegment<String>(
                      value: 'fa',
                      label: Text('فا'),
                    ),
                  ],
                  selected: <String>{settings.localeCode},
                  onSelectionChanged: (selection) =>
                      notifier.setLocaleCode(selection.first),
                ),
              ),
            ),
          ),
        ],
        initiallyExpanded: true,
      ),

      // ── Interface ─────────────────────────────────────────────────────
      _SettingsCategory(
        'Interface',
        Icons.palette_outlined,
        <_SettingsRow>[
          _SettingsRow(
            'theme mode light dark amoled system appearance',
            Semantics(
              label: 'Theme mode',
              child: SizedBox(
                height: AppConstants.touchTargetMin,
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('Light'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                    ),
                  ],
                  selected: <ThemeMode>{settings.themeMode},
                  onSelectionChanged: (selection) =>
                      notifier.setThemeMode(selection.first),
                ),
              ),
            ),
          ),
          _SettingsRow(
            'amoled black pure surfaces',
            SwitchListTile(
              key: const ValueKey<String>('settings-amoled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('AMOLED black'),
              subtitle: const Text('Pure black surfaces in dark mode'),
              value: settings.amoled,
              onChanged: settings.themeMode == ThemeMode.dark ||
                      settings.themeMode == ThemeMode.system
                  ? notifier.setAmoled
                  : null,
            ),
          ),
          _SettingsRow(
            'accent color purple green tint',
            Semantics(
              label: 'Accent color',
              child: SizedBox(
                height: AppConstants.touchTargetMin,
                width: double.infinity,
                child: SegmentedButton<AccentColor>(
                  showSelectedIcon: false,
                  segments: <ButtonSegment<AccentColor>>[
                    for (final accent in AccentColor.values)
                      ButtonSegment<AccentColor>(
                        value: accent,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: _accentSwatchSize,
                              height: _accentSwatchSize,
                              decoration: BoxDecoration(
                                color: accent.toWavelyAccent.colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: Spacing.xs),
                            Text(_accentLabel(accent)),
                          ],
                        ),
                      ),
                  ],
                  selected: <AccentColor>{settings.accent},
                  onSelectionChanged: (selection) =>
                      notifier.setAccent(selection.first),
                ),
              ),
            ),
          ),
          _SettingsRow(
            'reduce transparency disable blur effects glass',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce transparency'),
              subtitle: const Text('Disables blur effects'),
              value: settings.reduceTransparency,
              onChanged: notifier.setReduceTransparency,
            ),
          ),
          _SettingsRow(
            'accent from album art adaptive tint playing cover',
            SwitchListTile(
              key: const ValueKey<String>('settings-adaptive-accent'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Accent from album art'),
              subtitle: const Text('Tints the theme to the playing cover'),
              value: settings.adaptiveAccent,
              onChanged: notifier.setAdaptiveAccent,
            ),
          ),
          _SettingsRow(
            'blur strength strength backdrop scale',
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Blur strength — ${settings.blurScale.toStringAsFixed(1)}x',
                style: WavelyTypography.body14(color: colors.textPrimary),
              ),
              subtitle: Slider(
                key: const ValueKey<String>('settings-blur-slider'),
                value: settings.blurScale,
                min: 0,
                max: maxBlurScale,
                divisions: (maxBlurScale * 4).round(),
                label: '${settings.blurScale.toStringAsFixed(1)}x',
                onChanged: notifier.setBlurScale,
              ),
            ),
          ),
          _SettingsRow(
            'corner radius roundness scale',
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Corner radius — '
                '${settings.radiusScale.toStringAsFixed(1)}x',
                style: WavelyTypography.body14(color: colors.textPrimary),
              ),
              subtitle: Slider(
                key: const ValueKey<String>('settings-radius-slider'),
                value: settings.radiusScale,
                min: minRadiusScale,
                max: maxRadiusScale,
                divisions:
                    ((maxRadiusScale - minRadiusScale) * 4).round(),
                label: '${settings.radiusScale.toStringAsFixed(1)}x',
                onChanged: notifier.setRadiusScale,
              ),
            ),
          ),
        ],
        initiallyExpanded: true,
      ),

      // ── Audio ─────────────────────────────────────────────────────────
      _SettingsCategory(
        'Audio',
        Icons.graphic_eq_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'equalizer effects eq bassboost reverb replaygain profiles '
            'audio engine',
            ListTile(
              key: const ValueKey<String>('settings-audio-engine'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.equalizer_rounded),
              title: Text(
                'Equalizer & effects',
                style: WavelyTypography.body14(color: colors.textPrimary),
              ),
              subtitle: Text(
                '5-band EQ, BassBoost, Reverb, ReplayGain, profiles',
                style:
                    WavelyTypography.caption12(color: colors.textSecondary),
              ),
              onTap: () => unawaited(context.push(kAudioSettingsRoute)),
            ),
          ),
          _SettingsRow(
            'crossfade fade between tracks seconds',
            Semantics(
              label: 'Crossfade',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Crossfade — ${settings.crossfadeSeconds.round()}s',
                  style: WavelyTypography.body14(color: colors.textPrimary),
                ),
                subtitle: Slider(
                  key: const ValueKey<String>('settings-crossfade-slider'),
                  value: settings.crossfadeSeconds,
                  min: 0,
                  max: AppConstants.crossfadeMaxSeconds.toDouble(),
                  divisions: AppConstants.crossfadeMaxSeconds,
                  label: '${settings.crossfadeSeconds.round()}s',
                  onChanged: PlatformUtils.isWeb
                      ? null
                      : notifier.setCrossfade,
                ),
              ),
            ),
          ),
          _SettingsRow(
            'gapless playback engine supports',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gapless playback'),
              subtitle: const Text('Applied when the engine supports it'),
              value: settings.gaplessPlayback,
              onChanged: notifier.setGapless,
            ),
          ),
          _SettingsRow(
            'playback speed pitch tempo rate fast slow',
            Semantics(
              label: 'Playback speed',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Playback speed — '
                  '${_speedLabel(settings.playbackSpeed)}x',
                  style: WavelyTypography.body14(color: colors.textPrimary),
                ),
                subtitle: Slider(
                  key: const ValueKey<String>('settings-speed-slider'),
                  value: settings.playbackSpeed,
                  min: 0.5,
                  max: 2,
                  divisions: 6,
                  label: '${_speedLabel(settings.playbackSpeed)}x',
                  onChanged: notifier.setPlaybackSpeed,
                ),
              ),
            ),
          ),
        ],
      ),

      // ── Song Library & Tags ───────────────────────────────────────────
      _SettingsCategory(
        'Song Library & Tags',
        Icons.library_music_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'scan now rescan dialog total accessible excluded media store',
            ListTile(
              key: const Key('settings-scan-dialog-row'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.manage_search_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Scan library'),
              subtitle: const Text(
                'Scan now — totals, accessible and excluded files',
              ),
              onTap: () => unawaited(showScanDialog(context, ref)),
            ),
          ),
          _SettingsRow(
            'scan folders add remove media store sync library',
            _scanFoldersBlock(settings, notifier),
          ),
          _SettingsRow(
            'online sources subsonic navidrome jellyfin credentials',
            const SourcesSettingsSection(),
          ),
          _SettingsRow(
            'storage template downloads organization',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.description_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Storage template'),
              subtitle: Text(settings.storageTemplate),
              onTap: () => unawaited(_editStorageTemplate(context, ref)),
            ),
          ),
          _SettingsRow(
            'downloads queue active finished',
            ListTile(
              key: const Key('settings-downloads-row'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.download_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Downloads'),
              subtitle: const Text('Active, queued and finished downloads'),
              onTap: () => unawaited(context.push(downloadsRoute)),
            ),
          ),
          _SettingsRow(
            'download settings quality folder template wi-fi '
            'concurrency',
            ListTile(
              key: const Key('settings-download-settings-row'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.tune_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Download settings'),
              subtitle: const Text(
                'Quality, folder template, Wi-Fi-only, concurrency',
              ),
              onTap: () =>
                  unawaited(context.push(downloadSettingsRoute)),
            ),
          ),
        ],
      ),

      // ── Headset, Bluetooth & Speakers ────────────────────────────────
      _SettingsCategory(
        'Headset, Bluetooth & Speakers',
        Icons.headphones_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'resume on start restore queue position auto resume',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resume on start'),
              subtitle: const Text('Restore the last queue and position'),
              value: settings.resumeOnStart,
              onChanged: notifier.setResumeOnStart,
            ),
          ),
          _SettingsRow(
            'pause on unplug headphones bluetooth disconnect becoming '
            'noisy',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_rounded,
                color: colors.accentColors.accent,
              ),
              title: const Text('Pause on unplug'),
              subtitle: const Text(
                'Always on — playback pauses the moment headphones or a '
                'Bluetooth headset disconnects',
              ),
            ),
          ),
          _SettingsRow(
            'auto resume call navigation interruption bluetooth focus',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_rounded,
                color: colors.accentColors.accent,
              ),
              title: const Text('Resume after interruptions'),
              subtitle: const Text(
                'Always on — calls and navigation prompts pause playback, '
                'and it resumes when they end',
              ),
            ),
          ),
        ],
      ),

      // ── Notifications ────────────────────────────────────────────────
      _SettingsCategory(
        'Notifications',
        Icons.notifications_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'media controls lock screen notification playing',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_rounded,
                color: colors.accentColors.accent,
              ),
              title: const Text('Media notification & controls'),
              subtitle: const Text(
                'System media controls with play/pause, next, previous '
                'and seek appear while playing',
              ),
            ),
          ),
          _SettingsRow(
            'check for updates release github badge version',
            ListTile(
              key: const Key('settings-updates-row'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.system_update_alt_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Check for updates'),
              subtitle: Text(
                updateBadge
                    ? 'Update available — tap to review'
                    : 'Releases are published on GitHub',
              ),
              trailing: updateBadge
                  ? Container(
                      key: const Key('settings-updates-badge'),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.accentColors.accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
              onTap: () => unawaited(context.push(UpdateScreen.route)),
            ),
          ),
          _SettingsRow(
            'news music updates sources settings digest',
            ListTile(
              key: const Key('settings-news-row'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.newspaper_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('News'),
              subtitle: const Text('Music news from legal, no-key sources'),
              onTap: () => unawaited(context.push(newsRoute)),
            ),
          ),
        ],
      ),

      // ── HomeScreen Widgets ───────────────────────────────────────────
      _SettingsCategory(
        'HomeScreen Widgets',
        Icons.widgets_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'home screen widgets widget sync queue state launcher tile',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_rounded,
                color: colors.accentColors.accent,
              ),
              title: const Text('Home-screen widget sync'),
              subtitle: const Text(
                'The queue, track and play state are published to the '
                'home-screen widgets and quick tile automatically',
              ),
            ),
          ),
        ],
      ),

      // ── Lock Screen ──────────────────────────────────────────────────
      _SettingsCategory(
        'Lock Screen',
        Icons.lock_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'lock screen media controls artwork queue',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.check_circle_rounded,
                color: colors.accentColors.accent,
              ),
              title: const Text('Lock-screen controls'),
              subtitle: const Text(
                'The system lock screen shows the track, artwork and '
                'transport controls while playing',
              ),
            ),
          ),
        ],
      ),

      // ── Advanced ─────────────────────────────────────────────────────
      _SettingsCategory(
        'Advanced',
        Icons.tune_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'discover new music artists follow',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.auto_awesome_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Discover'),
              subtitle: const Text('New music from artists you follow'),
              onTap: () => unawaited(context.push(DiscoveryScreen.route)),
            ),
          ),
          _SettingsRow(
            'your stats top tracks artists listening time analytics',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.bar_chart_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Your stats'),
              subtitle: const Text('Top tracks, artists and listening time'),
              onTap: () => unawaited(context.push(AnalyticsScreen.route)),
            ),
          ),
          _SettingsRow(
            'ai dj queue own words assistant chat',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.smart_toy_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('AI DJ'),
              subtitle: const Text('Ask for a queue in your own words'),
              onTap: () => unawaited(context.push(AiChatScreen.route)),
            ),
          ),
          _SettingsRow(
            'parental controls family safe languages filter',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.family_restroom_rounded,
                color: colors.textSecondary,
              ),
              title: const Text('Parental controls'),
              onTap: () => unawaited(context.push(ParentalScreen.route)),
            ),
          ),
          _SettingsRow(
            'cache size temporary files megabytes',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.folder_zip_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Cache size'),
              subtitle: Text(_cacheLabel(ref.watch(cacheSizeProvider))),
            ),
          ),
          _SettingsRow(
            'clear cache cleanup temporary covers',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.cleaning_services_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Clear cache'),
              onTap: () => unawaited(_clearCache(context, ref)),
            ),
          ),
        ],
      ),

      // ── Backup & Restore ─────────────────────────────────────────────
      _SettingsCategory(
        'Backup & Restore',
        Icons.backup_rounded,
        <_SettingsRow>[
          _SettingsRow(
            'account sign in sync devices backup cloud restore',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.person_outline,
                color: colors.textSecondary,
              ),
              title: const Text('Account & sync'),
              subtitle: const Text(
                'Sign in to back up plays, favorites and settings across '
                'devices',
              ),
              onTap: () => unawaited(context.push(WelcomeScreen.route)),
            ),
          ),
        ],
      ),

      // ── About ────────────────────────────────────────────────────────
      _SettingsCategory(
        'About',
        Icons.info_outline,
        <_SettingsRow>[
          _SettingsRow(
            'version build number wavely',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.info_outline,
                color: colors.textSecondary,
              ),
              title: const Text('Version'),
              subtitle: Text(_versionLabel(ref.watch(packageInfoProvider))),
            ),
          ),
          _SettingsRow(
            'open source licenses',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.article_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Open source licenses'),
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Wavely'),
            ),
          ),
          _SettingsRow(
            'privacy policy data analytics pii',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.privacy_tip_outlined,
                color: colors.textSecondary,
              ),
              title: const Text('Privacy policy'),
              onTap: () => unawaited(_showPrivacyDialog(context)),
            ),
          ),
          _SettingsRow(
            'github source code repository dani devlop',
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.code,
                color: colors.textSecondary,
              ),
              title: const Text('GitHub'),
              subtitle: const Text('github.com/Dani-Devlop/Music_Wavely'),
              onTap: () => unawaited(_openGitHub(context, ref)),
            ),
          ),
        ],
      ),
    ];
  }

  // -- blocks ---------------------------------------------------------------

  /// The scan-folders block (list + add button) used inside the
  /// Song Library & Tags category.
  Widget _scanFoldersBlock(AppSettings settings, SettingsNotifier notifier) {
    final colors = context.wavelyColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Scan folders',
          style: WavelyTypography.body14Medium(color: colors.textSecondary),
        ),
        if (settings.scanFolders.isEmpty)
          Text(
            'No folders yet. Add one to start scanning.',
            style: WavelyTypography.caption12(color: colors.textTertiary),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: settings.scanFolders.length,
            itemBuilder: (context, index) {
              final folder = settings.scanFolders[index];
              return ListTile(
                key: ValueKey<String>('settings-folder-$folder'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.folder_outlined,
                  color: colors.textSecondary,
                ),
                title: Text(
                  folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WavelyTypography.body14(
                    color: colors.textPrimary,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: colors.textTertiary,
                  ),
                  tooltip: 'Remove folder',
                  onPressed: () => notifier.removeScanFolder(folder),
                ),
              );
            },
          ),
        FilledButton.tonalIcon(
          onPressed: () => unawaited(_addFolder(ref)),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add folder'),
        ),
      ],
    );
  }

  // -- helpers --------------------------------------------------------------

  static String _accentLabel(AccentColor accent) => switch (accent) {
        AccentColor.purple => 'Purple',
        AccentColor.green => 'Green',
      };

  static String _speedLabel(double speed) => speed == speed.roundToDouble()
      ? '${speed.round()}'
      : '$speed';

  static String _versionLabel(AsyncValue<PackageInfo> info) => info.maybeWhen(
        data: (value) => 'Wavely ${value.version} (${value.buildNumber})',
        orElse: () => 'Wavely',
      );

  static String _cacheLabel(AsyncValue<int> size) => size.maybeWhen(
        data: (bytes) => '${(bytes / _bytesPerMb).round()} MB',
        orElse: () => '—',
      );

  Future<void> _addFolder(WidgetRef ref) async {
    final picked = await ref.read(libraryScannerProvider).pickFolders();
    if (picked.isEmpty) {
      return;
    }
    for (final folder in picked) {
      ref.read(settingsProvider.notifier).addScanFolder(folder);
    }
    // Kick a scan over the newly picked folders (same flow as the Folders
    // tab; the notifier invalidates the library providers on completion).
    ref.read(scanStateProvider.notifier).startScan(picked);
  }

  Future<void> _editStorageTemplate(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(settingsProvider).storageTemplate;
    final controller = TextEditingController(text: current);
    final template = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Storage template'),
        content: TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Template',
            helperText: 'Reserved for future download organization '
                '(unused in Stage 1.1)',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (template == null || template.isEmpty) {
      return;
    }
    ref.read(settingsProvider.notifier).setStorageTemplate(template);
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cache?'),
        content: const Text('Removes temporary files and cached cover art.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final result = await clearAppCaches();
    ref.invalidate(cacheSizeProvider);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result)));
  }

  Future<void> _showPrivacyDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Privacy policy'),
        content: const Text(
          'Wavely collects no analytics and no personal data. '
          'Crash reports contain no PII.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Opens the GitHub repo in the external browser. Falls back to a
  /// SnackBar when the platform reports no handler for the link (the URL is
  /// still visible so the user can copy it).
  Future<void> _openGitHub(BuildContext context, WidgetRef ref) async {
    final url = Uri.parse(_gitHubUrl);
    final launched =
        await ref.read(linkLauncherProvider).launchExternal(url);
    if (launched || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open in browser: $_gitHubUrl')),
    );
  }
}

/// One expandable category card in the tree: surface container, icon +
/// title header (ExpansionTile) and the deep rows inside.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.searching});

  final _SettingsCategory category;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      // ListTile/ExpansionTile paint on the nearest Material; without this
      // the decorated container hides ink splashes (framework assertion).
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          // Musicolet-style: no divider lines, tight tile height, accent
          // icon always visible in the header row.
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: category.initiallyExpanded || searching,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.lg,
            ),
            leading: Icon(
              category.icon,
              color: colors.accentColors.accent,
            ),
            title: Text(
              category.title,
              style: WavelyTypography.body14Medium(color: colors.textPrimary),
            ),
            children: <Widget>[
              for (final row in category.rows)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: row.widget,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
