import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/downloads/data/download_prefs.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';

/// Route for the download settings screen.
const String downloadSettingsRoute = '/downloads/settings';

/// Quality / folder template / storage location / Wi-Fi-only / concurrency.
class DownloadSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const DownloadSettingsScreen({super.key});

  @override
  ConsumerState<DownloadSettingsScreen> createState() =>
      _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState
    extends ConsumerState<DownloadSettingsScreen> {
  late final TextEditingController _templateController;
  late final TextEditingController _dirController;

  @override
  void initState() {
    super.initState();
    final DownloadPrefs prefs = ref.read(downloadPrefsProvider);
    _templateController = TextEditingController(text: prefs.folderTemplate);
    _dirController = TextEditingController(text: prefs.baseDir);
  }

  @override
  void dispose() {
    _templateController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final DownloadPrefs prefs = ref.watch(downloadPrefsProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Download settings'),
        backgroundColor: colors.bgBase,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: <Widget>[
          // --- Quality ------------------------------------------------
          Text('Quality', style: TextStyle(color: colors.textSecondary)),
          const SizedBox(height: Spacing.sm),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: '320', label: Text('320 kbps')),
              ButtonSegment<String>(value: 'flac', label: Text('FLAC')),
              ButtonSegment<String>(value: 'original', label: Text('Original')),
            ],
            selected: <String>{prefs.quality},
            onSelectionChanged: (Set<String> s) async {
              await ref
                  .read(downloadPrefsProvider)
                  .setQuality(s.first);
              setState(() {});
            },
          ),
          const SizedBox(height: Spacing.lg),

          // --- Folder template ----------------------------------------
          Text(
            'Folder template',
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('folder-template-field'),
            controller: _templateController,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(
              hintText:
                  'Placeholders: {continent} {country} {genre} {artist} '
                  '{album} {year} {title} {trackNumber}',
            ),
            onSubmitted: (String v) async {
              await ref
                  .read(downloadPrefsProvider)
                  .setFolderTemplate(v.trim().isEmpty
                      ? FolderTemplateDefault
                      : v.trim());
              setState(() {});
            },
          ),
          const SizedBox(height: Spacing.lg),

          // --- Storage location ---------------------------------------
          Text(
            'Storage location',
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            key: const Key('storage-location-field'),
            controller: _dirController,
            style: TextStyle(color: colors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Empty = platform default music directory',
            ),
            onSubmitted: (String v) async {
              await ref.read(downloadPrefsProvider).setBaseDir(v.trim());
              setState(() {});
            },
          ),
          const SizedBox(height: Spacing.lg),

          // --- Wi-Fi only ----------------------------------------------
          SwitchListTile(
            key: const Key('wifi-only-switch'),
            title: Text(
              'Wi-Fi only',
              style: TextStyle(color: colors.textPrimary),
            ),
            subtitle: Text(
              'Download only on unmetered networks',
              style: TextStyle(color: colors.textSecondary),
            ),
            value: prefs.wifiOnly,
            onChanged: (bool v) async {
              await ref.read(downloadPrefsProvider).setWifiOnly(v);
              setState(() {});
            },
          ),

          // --- Concurrency ---------------------------------------------
          Text(
            'Concurrent downloads: ${prefs.concurrency}',
            style: TextStyle(color: colors.textSecondary),
          ),
          Slider(
            key: const Key('concurrency-slider'),
            value: prefs.concurrency.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '${prefs.concurrency}',
            onChanged: (double v) async {
              await ref
                  .read(downloadPrefsProvider)
                  .setConcurrency(v.round());
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
