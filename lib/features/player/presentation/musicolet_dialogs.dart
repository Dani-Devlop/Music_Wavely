/// Musicolet-parity custom dialogs (v1.0.2 Android UI).
///
/// The owner spec bans default AlertDialogs for these flows:
/// - **Scan dialog** — big green SCAN NOW button with live text stats
///   (Total songs / Accessible / Excluded) wired to the REAL library
///   scanner.
/// - **Sleep-timer dialog** — the exact Musicolet button set
///   (0:15:00, 1:30:00, h:mm, N=5, N=10, After a specific song) wired to
///   the REAL queue manager's sleep timer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/library/presentation/library_providers.dart';
import 'package:wavely/features/player/presentation/musicolet_palette.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Opens the Musicolet scan dialog.
Future<void> showScanDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => const _ScanDialog(),
  );
}

class _ScanDialog extends ConsumerStatefulWidget {
  const _ScanDialog();

  @override
  ConsumerState<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends ConsumerState<_ScanDialog> {
  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanStateProvider);
    final settings = ref.watch(settingsProvider);
    final count = ref.watch(libraryCountProvider).value ?? 0;
    final accessible = scan.lastCount > 0 ? scan.lastCount : count;
    final excluded = scan.errors.length;
    return Dialog(
      backgroundColor: MusicoletColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.manage_search_rounded,
                    color: MusicoletColors.green),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Scan library',
                    style: WavelyTypography.title18(
                      color: MusicoletColors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close,
                      color: MusicoletColors.textDim),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            _StatRow(label: 'Total songs', value: '$count'),
            _StatRow(
              label: 'Accessible',
              value: scan.scanning
                  ? '${scan.processed}/${scan.total}'
                  : '$accessible',
            ),
            _StatRow(label: 'Excluded', value: '$excluded'),
            if (scan.scanning) ...<Widget>[
              const SizedBox(height: Spacing.md),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: scan.total > 0
                      ? (scan.processed / scan.total).clamp(0.0, 1.0)
                      : null,
                  backgroundColor: MusicoletColors.sheetCard,
                  color: MusicoletColors.green,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                scan.currentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WavelyTypography.micro10(
                  color: MusicoletColors.textDim,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('scan-dialog-now'),
                style: FilledButton.styleFrom(
                  backgroundColor: MusicoletColors.green,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: MusicoletColors.green.withValues(
                    alpha: 0.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: settings.scanFolders.isEmpty || scan.scanning
                    ? null
                    : () {
                        ref
                            .read(scanStateProvider.notifier)
                            .startScan(settings.scanFolders);
                      },
                icon: const Icon(Icons.refresh_rounded, size: 24),
                label: Text(
                  scan.scanning ? 'SCANNING…' : 'SCAN NOW',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            if (settings.scanFolders.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.sm),
                child: Text(
                  'Add a scan folder in Settings → Song Library & Tags '
                  'first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MusicoletColors.textDim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: WavelyTypography.body14(color: MusicoletColors.text),
              ),
            ),
            Text(
              value,
              style: WavelyTypography.body14Medium(
                color: MusicoletColors.green,
              ),
            ),
          ],
        ),
      );
}

/// Opens the Musicolet sleep-timer dialog.
Future<void> showSleepTimerDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => const _SleepTimerDialog(),
  );
}

class _SleepTimerDialog extends ConsumerStatefulWidget {
  const _SleepTimerDialog();

  @override
  ConsumerState<_SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends ConsumerState<_SleepTimerDialog> {
  int _customHours = 0;
  int _customMinutes = 30;

  @override
  Widget build(BuildContext context) {
    final manager = ref.read(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final endsAt = queue.sleepTimerEndsAt;
    return Dialog(
      backgroundColor: MusicoletColors.sheet,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.timer_outlined,
                    color: MusicoletColors.green),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Sleep timer',
                    style: WavelyTypography.title18(
                      color: MusicoletColors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close,
                      color: MusicoletColors.textDim),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            _TimerButton(
              label: '0:15:00',
              onTap: () => _popThen(() =>
                  manager.startSleepTimer(const Duration(minutes: 15))),
            ),
            _TimerButton(
              label: '1:30:00',
              onTap: () => _popThen(() =>
                  manager.startSleepTimer(const Duration(minutes: 90))),
            ),
            _TimerButton(
              label: 'h:mm',
              subtitle: 'Custom duration',
              onTap: _confirmCustom,
            ),
            _TimerButton(
              label: 'N=5',
              subtitle: 'Pause after 5 songs',
              onTap: () => _popThen(() => _startAfterSongs(manager, 5)),
            ),
            _TimerButton(
              label: 'N=10',
              subtitle: 'Pause after 10 songs',
              onTap: () => _popThen(() => _startAfterSongs(manager, 10)),
            ),
            _TimerButton(
              label: 'After a specific song',
              subtitle: 'When this song ends',
              onTap: () => _popThen(() => _startAfterCurrent(manager)),
            ),
            if (endsAt != null) ...<Widget>[
              const SizedBox(height: Spacing.sm),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF5350),
                    side: const BorderSide(color: Color(0xFFEF5350)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    manager.cancelSleepTimer();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel timer'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _popThen(VoidCallback action) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  Future<void> _confirmCustom() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: MusicoletColors.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: StatefulBuilder(
          builder: (context, setState2) => Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Custom duration',
                  style: WavelyTypography.title18(
                    color: MusicoletColors.text,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _NumberColumn(
                      label: 'h',
                      value: _customHours,
                      max: 23,
                      onChanged: (v) => setState2(() => _customHours = v),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Spacing.md),
                      child: Text(
                        ':',
                        style: TextStyle(
                          color: MusicoletColors.text,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    _NumberColumn(
                      label: 'mm',
                      value: _customMinutes,
                      max: 59,
                      onChanged: (v) => setState2(() => _customMinutes = v),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: MusicoletColors.green,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      final manager = ref.read(queueManagerProvider.notifier);
      manager.startSleepTimer(
        Duration(hours: _customHours, minutes: _customMinutes),
      );
    }
  }

  /// "Pause after N songs": scheduled from the REAL durations of the next
  /// N tracks in the queue (the honest, existing-API approximation).
  void _startAfterSongs(QueueManager manager, int count) {
    final queue = ref.read(queueManagerProvider);
    if (queue.tracks.isEmpty) {
      return;
    }
    final start = (queue.currentIndex + 1).clamp(0, queue.tracks.length);
    final end = (start + count).clamp(0, queue.tracks.length);
    var ms = 0;
    for (var i = start; i < end; i++) {
      ms += queue.tracks[i].durationMs;
    }
    if (ms <= 0) {
      return;
    }
    manager.startSleepTimer(Duration(milliseconds: ms));
  }

  /// "After a specific song": timer equals the remaining time of the
  /// current track (duration − position).
  void _startAfterCurrent(QueueManager manager) {
    final queue = ref.read(queueManagerProvider);
    final remaining = queue.duration - queue.position;
    if (remaining <= Duration.zero) {
      return;
    }
    manager.startSleepTimer(remaining);
  }
}

/// One big Musicolet timer option button.
class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: MusicoletColors.text,
            side: const BorderSide(color: MusicoletColors.divider),
            backgroundColor: MusicoletColors.sheetCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: AlignmentDirectional.centerStart,
          ),
          onPressed: onTap,
          child: Row(
            children: <Widget>[
              const Icon(Icons.schedule_rounded,
                  size: 18, color: MusicoletColors.green),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: WavelyTypography.body14Medium(
                        color: MusicoletColors.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: WavelyTypography.micro10(
                          color: MusicoletColors.textDim,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple +/- number stepper column (h / mm picker).
class _NumberColumn extends StatelessWidget {
  const _NumberColumn({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.expand_less,
              color: MusicoletColors.green),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
        Text(
          '$value'.padLeft(label == 'mm' ? 2 : 1, '0'),
          style: const TextStyle(
            color: MusicoletColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: WavelyTypography.micro10(color: MusicoletColors.textDim),
        ),
        IconButton(
          icon: const Icon(Icons.expand_more,
              color: MusicoletColors.green),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
      ],
    );
  }
}
