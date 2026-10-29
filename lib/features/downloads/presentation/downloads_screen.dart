import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/downloads/data/download_service.dart';
import 'package:wavely/features/downloads/data/downloads_providers.dart';

/// Route for the downloads screen.
const String downloadsRoute = '/downloads';

/// Live section queries for the downloads screen.
final activeDownloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  return ref.watch(databaseProvider).downloadsDao
      .watchByStatuses(<DownloadStatus>[DownloadStatus.downloading]);
});

final queuedDownloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  return ref.watch(databaseProvider).downloadsDao
      .watchByStatuses(<DownloadStatus>[DownloadStatus.queued]);
});

final completedDownloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  return ref.watch(databaseProvider).downloadsDao
      .watchByStatuses(<DownloadStatus>[DownloadStatus.completed]);
});

final failedDownloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  return ref.watch(databaseProvider).downloadsDao
      .watchByStatuses(<DownloadStatus>[DownloadStatus.failed]);
});

/// Downloads screen: Active / Queued / Completed / Failed sections with
/// per-row progress, pause/resume, cancel and retry.
class DownloadsScreen extends ConsumerWidget {
  /// Creates the screen.
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        title: const Text('Downloads'),
        backgroundColor: colors.bgBase,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: <Widget>[
          _Section(
            title: 'Active',
            provider: activeDownloadsProvider,
            buildRow: (BuildContext c, WidgetRef r, DownloadRow row) =>
                _DownloadTile(
              row: row,
              onResume: null,
              onPause: () =>
                  _withService(r, (DownloadService s) => s.pause(row.id)),
              onCancel: () =>
                  _withService(r, (DownloadService s) => s.cancel(row.id)),
              onRetry: null,
            ),
          ),
          _Section(
            title: 'Queued',
            provider: queuedDownloadsProvider,
            buildRow: (BuildContext c, WidgetRef r, DownloadRow row) =>
                _DownloadTile(
              row: row,
              onResume: null,
              onPause: () =>
                  _withService(r, (DownloadService s) => s.pause(row.id)),
              onCancel: () =>
                  _withService(r, (DownloadService s) => s.cancel(row.id)),
              onRetry: null,
            ),
          ),
          _Section(
            title: 'Completed',
            provider: completedDownloadsProvider,
            buildRow: (BuildContext c, WidgetRef r, DownloadRow row) =>
                _DownloadTile(row: row),
          ),
          _Section(
            title: 'Failed',
            provider: failedDownloadsProvider,
            buildRow: (BuildContext c, WidgetRef r, DownloadRow row) =>
                _DownloadTile(
              row: row,
              onRetry: () =>
                  _withService(r, (DownloadService s) => s.retry(row.id)),
              onCancel: () =>
                  _withService(r, (DownloadService s) => s.cancel(row.id)),
              onPause: null,
              onResume: null,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _withService(
    WidgetRef ref,
    Future<void> Function(DownloadService) action,
  ) async {
    final AsyncValue<DownloadService> service =
        ref.read(downloadServiceProvider);
    final DownloadService? s = service.asData?.value;
    if (s != null) {
      await action(s);
    }
  }
}

class _Section extends ConsumerWidget {
  const _Section({
    required this.title,
    required this.provider,
    required this.buildRow,
  });

  final String title;
  final StreamProvider<List<DownloadRow>> provider;
  final Widget Function(BuildContext, WidgetRef, DownloadRow) buildRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final AsyncValue<List<DownloadRow>> state = ref.watch(provider);
    final List<DownloadRow> rows = state.asData?.value ?? const <DownloadRow>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (rows.isEmpty)
          Text(
            'Nothing here.',
            style: TextStyle(color: colors.textTertiary),
          )
        else
          ...rows.map(
            (DownloadRow row) => buildRow(context, ref, row),
          ),
        const SizedBox(height: Spacing.lg),
      ],
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({
    required this.row,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
  });

  final DownloadRow row;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    return Card(
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${row.sourceId} · ${row.sourceTrackId}',
                    style: TextStyle(color: colors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${row.progress}%',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            LinearProgressIndicator(
              value: row.progress / 100,
              minHeight: 4,
            ),
            if (row.errorMessage != null) ...<Widget>[
              const SizedBox(height: Spacing.xs),
              Text(
                row.errorMessage!,
                style: TextStyle(color: colors.textTertiary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (onPause != null)
                  IconButton(
                    key: ValueKey('pause-${row.id}'),
                    tooltip: 'Pause',
                    icon: const Icon(Icons.pause_rounded),
                    onPressed: () => onPause!(),
                  ),
                if (onResume != null)
                  IconButton(
                    key: ValueKey('resume-${row.id}'),
                    tooltip: 'Resume',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => onResume!(),
                  ),
                if (onRetry != null)
                  IconButton(
                    key: ValueKey('retry-${row.id}'),
                    tooltip: 'Retry',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => onRetry!(),
                  ),
                if (onCancel != null)
                  IconButton(
                    key: ValueKey('cancel-${row.id}'),
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => onCancel!(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
