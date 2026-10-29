import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/data/sync/sync_providers.dart';
import 'package:wavely/data/sync/sync_status.dart';
import 'package:wavely/design_system/design_system.dart';

/// Live sync engine state for the settings screen.
///
/// Falls back to `SyncStatus.idle` before the first emission so the badge is
/// always renderable.
final syncStatusStreamProvider = StreamProvider<SyncStatusView>((ref) {
  return ref.watch(syncServiceProvider).statusStream;
});

/// Solid pill showing the sync status icon + label (+ pending outbox count).
///
/// Named `SyncStatusBadge` (not `SyncStatusView` — that name is taken by the
/// DATA class in `lib/data/sync/sync_status.dart` that this widget renders;
/// both were specced as "SyncStatusView", the widget got a distinct name to
/// avoid the import clash). Deliberately a solid container: no
/// [BackdropFilter], so it can live on any screen without blowing the
/// per-screen blur budget.
class SyncStatusBadge extends ConsumerWidget {
  /// Creates the badge.
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final async = ref.watch(syncStatusStreamProvider);
    final view =
        async.value ?? const SyncStatusView(status: SyncStatus.idle);
    final (icon, label) = switch (view.status) {
      SyncStatus.disabled => (Icons.cloud_off_outlined, 'Sync off'),
      SyncStatus.idle => (Icons.cloud_done_outlined, 'Synced'),
      SyncStatus.syncing => (Icons.cloud_upload_outlined, 'Syncing…'),
      SyncStatus.error => (Icons.sync_problem, 'Sync error'),
    };
    final pendingLabel = view.pending > 0 ? ' · ${view.pending}' : '';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.bPill,
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 16,
            color: view.status == SyncStatus.error
                ? colors.error
                : colors.textSecondary,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            '$label$pendingLabel',
            style: WavelyTypography.caption12(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
