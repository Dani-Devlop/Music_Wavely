import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/utils/platform_utils.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/data/library_scanner_provider.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';

/// Height of the placeholder rows shown while folders load.
const double _shimmerRowHeight = 72;

/// Number of placeholder rows shown while folders load.
const int _shimmerRowCount = 4;

/// Maximum number of scan problems displayed inline.
const int _maxInlineScanErrors = 3;

/// Folders tab: manage scanned folders and watch the scan progress. The
/// 2026 redesign replaces the plain ListTiles with rich folder cards
/// (gradient folder tile, name + full path, persisted track-count badge,
/// remove action) and staggers their entrance.
class FoldersTab extends ConsumerWidget {
  /// Creates the folders tab.
  const FoldersTab({super.key});

  Future<void> _addFolder(WidgetRef ref) async {
    final picked = await ref.read(libraryScannerProvider).pickFolders();
    if (picked.isEmpty) {
      return;
    }
    final merged = await addScanFolders(ref, picked);
    ref.read(scanStateProvider.notifier).startScan(merged);
  }

  Future<void> _rescanAll(WidgetRef ref) async {
    final folders = await ref.read(foldersProvider.future);
    ref.read(scanStateProvider.notifier).startScan(folders);
  }

  Future<void> _removeFolder(WidgetRef ref, String folder) async {
    await removeScanFolder(ref, folder);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final foldersAsync = ref.watch(foldersProvider);
    final scanState = ref.watch(scanStateProvider);
    final trackCount = ref.watch(libraryCountProvider).asData?.value ?? 0;

    if (PlatformUtils.isWeb) {
      return const EmptyState(
        icon: Icons.cloud_off,
        title: 'Scanning unavailable on web',
        subtitle:
            'Browsers cannot read local music folders. '
            'Use the desktop or mobile app to build your library.',
      );
    }

    return foldersAsync.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        itemCount: _shimmerRowCount,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: ShimmerBox(height: _shimmerRowHeight),
        ),
      ),
      error: (error, stackTrace) => ErrorState(
        message: 'Could not load your folders',
        detail: error.toString(),
        onRetry: () => ref.invalidate(foldersProvider),
      ),
      data: (folders) => ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: scanState.scanning
                      ? null
                      : () {
                          unawaited(_addFolder(ref));
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add folder'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (scanState.scanning || folders.isEmpty)
                      ? null
                      : () {
                          unawaited(_rescanAll(ref));
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Rescan all'),
                ),
              ),
            ],
          ),
          if (scanState.scanning) ...<Widget>[
            const SizedBox(height: Spacing.lg),
            const SectionHeader(title: 'Scanning'),
            ClipRRect(
              borderRadius: AppRadii.bPill,
              child: LinearProgressIndicator(
                value: scanState.progress,
                backgroundColor: colors.borderGlass,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              scanState.total > 0
                  ? '${scanState.processed} of ${scanState.total} — '
                      '${scanState.currentFile}'
                  : 'Looking for audio files…',
              style: WavelyTypography.caption12(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (!scanState.scanning &&
              scanState.errors.isNotEmpty) ...<Widget>[
            const SizedBox(height: Spacing.lg),
            const SectionHeader(title: 'Scan problems'),
            for (final error in scanState.errors.take(_maxInlineScanErrors))
              Text(
                error,
                style: WavelyTypography.caption12(color: colors.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          if (folders.isNotEmpty) ...<Widget>[
            const SizedBox(height: Spacing.lg),
            const SectionHeader(title: 'Folders'),
            const SizedBox(height: Spacing.xs),
            for (var i = 0; i < folders.length; i++)
              StaggeredAppear(
                index: i,
                child: _FolderCard(
                  folder: folders[i],
                  colors: colors,
                  onRemove: () {
                    unawaited(_removeFolder(ref, folders[i]));
                  },
                ),
              ),
          ],
          if (trackCount == 0 && !scanState.scanning) ...<Widget>[
            const SizedBox(height: Spacing.xl),
            EmptyState(
              icon: Icons.library_music,
              title: 'No music yet',
              subtitle:
                  'Add a folder with your own audio files and Wavely will '
                  'index it locally.',
              ctaLabel: 'Add folder',
              onCta: () {
                unawaited(_addFolder(ref));
              },
            ),
          ],
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

/// Rich folder card: gradient folder tile, folder name, full path caption
/// and the persisted track-count badge for that folder.
class _FolderCard extends ConsumerWidget {
  const _FolderCard({
    required this.folder,
    required this.colors,
    required this.onRemove,
  });

  final String folder;
  final WavelySemanticColors colors;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(folderTrackCountsProvider).asData?.value;
    final trackCount = counts?[folder];
    final accent = colors.accentColors;
    // Windows (\) and POSIX (/) separators both accepted — the folder list
    // travels across desktop and Android.
    final name = folder.split(RegExp(r'[/\\]')).last;
    return Container(
      key: ValueKey<String>('folder-$folder'),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bLg,
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: AppRadii.bMd,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  accent.accent.withValues(alpha: 0.85),
                  accent.gradientStart.withValues(alpha: 0.9),
                ],
              ),
            ),
            child: const Icon(
              Icons.folder_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name.isEmpty ? folder : name,
                  style: WavelyTypography.body14Medium(
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  folder,
                  style: WavelyTypography.caption12(
                    color: colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          if (trackCount != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm + 2,
                vertical: Spacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.accent.withValues(alpha: 0.14),
                borderRadius: AppRadii.bPill,
                border: Border.all(color: accent.accent.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$trackCount tracks',
                style: WavelyTypography.micro10(color: accent.accent),
              ),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.textTertiary),
            tooltip: 'Remove folder',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
