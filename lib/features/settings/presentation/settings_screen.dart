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
import 'package:wavely/features/auth/presentation/welcome_screen.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/parental/presentation/parental_screen.dart';
import 'package:wavely/features/settings/data/cache_cleaner.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/domain/settings.dart';

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

/// Settings root screen.
///
/// Section groups use a solid token-styled container ([_SectionGroup]) —
/// deliberately NOT [GlassCard]: four groups would exceed
/// [AppConstants.maxBackdropFiltersPerScreen] (3), so no BackdropFilter is
/// rendered on this screen.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  /// Route path for Task 4's router.
  static const String route = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Settings',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: <Widget>[
          _SectionGroup(
            title: 'Appearance',
            children: <Widget>[
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
              const SizedBox(height: Spacing.md),
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
                                  color:
                                      accent.toWavelyAccent().colors.accent,
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce transparency'),
                subtitle: const Text('Disables blur effects'),
                value: settings.reduceTransparency,
                onChanged: notifier.setReduceTransparency,
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _SectionGroup(
            title: 'Playback',
            children: <Widget>[
              Semantics(
                label: 'Crossfade',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Crossfade — ${settings.crossfadeSeconds.round()}s',
                    style: WavelyTypography.body14(color: colors.textPrimary),
                  ),
                  subtitle: Slider(
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gapless playback'),
                subtitle: const Text('Applied when the engine supports it'),
                value: settings.gaplessPlayback,
                onChanged: notifier.setGapless,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Resume on start'),
                subtitle: const Text('Restore the last queue and position'),
                value: settings.resumeOnStart,
                onChanged: notifier.setResumeOnStart,
              ),
              Semantics(
                label: 'Playback speed',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Playback speed — ${_speedLabel(settings.playbackSpeed)}x',
                    style: WavelyTypography.body14(color: colors.textPrimary),
                  ),
                  subtitle: Slider(
                    value: settings.playbackSpeed,
                    min: 0.5,
                    max: 2,
                    divisions: 6,
                    label: '${_speedLabel(settings.playbackSpeed)}x',
                    onChanged: notifier.setPlaybackSpeed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _SectionGroup(
            title: 'Storage',
            children: <Widget>[
              _fieldLabel(context, 'Scan folders'),
              if (settings.scanFolders.isEmpty)
                Text(
                  'No folders yet. Add one to start scanning.',
                  style:
                      WavelyTypography.caption12(color: colors.textTertiary),
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
              const SizedBox(height: Spacing.md),
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
              Text(
                'Reserved for future download organization '
                '(unused in Stage 1.1)',
                style: WavelyTypography.caption12(color: colors.textTertiary),
              ),
              const SizedBox(height: Spacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.folder_zip_outlined,
                  color: colors.textSecondary,
                ),
                title: const Text('Cache size'),
                subtitle: Text(_cacheLabel(ref.watch(cacheSizeProvider))),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: colors.textSecondary,
                ),
                title: const Text('Clear cache'),
                onTap: () => unawaited(_clearCache(context, ref)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _SectionGroup(
            title: 'More',
            children: <Widget>[
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.family_restroom_rounded,
                  color: colors.textSecondary,
                ),
                title: const Text('Parental controls'),
                onTap: () => unawaited(context.push(ParentalScreen.route)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.person_outline,
                  color: colors.textSecondary,
                ),
                title: const Text('Account'),
                subtitle: const Text('Sign in to sync across devices'),
                onTap: () => unawaited(context.push(WelcomeScreen.route)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          _SectionGroup(
            title: 'About',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.info_outline,
                  color: colors.textSecondary,
                ),
                title: const Text('Version'),
                subtitle: Text(_versionLabel(ref.watch(packageInfoProvider))),
              ),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: colors.textSecondary,
                ),
                title: const Text('Privacy policy'),
                onTap: () => unawaited(_showPrivacyDialog(context)),
              ),
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
            ],
          ),
        ],
      ),
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

  Widget _fieldLabel(BuildContext context, String label) {
    final colors = context.wavelyColors;
    return Text(
      label,
      style: WavelyTypography.body14Medium(color: colors.textSecondary),
    );
  }

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

/// Solid, token-styled section container (surface tint + borderGlass +
/// AppRadii) — a GlassCard replacement that renders NO BackdropFilter.
class _SectionGroup extends StatelessWidget {
  const _SectionGroup({required this.title, required this.children});

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
