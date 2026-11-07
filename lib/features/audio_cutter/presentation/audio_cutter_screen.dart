/// Audio cutter screen (Phase 7.2).
///
/// Waveform canvas (peak envelope over the decoded PCM) with draggable
/// start/end handles, editable timestamps (`mm:ss(.mmm)`), trim /
/// extract-to-new-file, and the "set as ringtone / notification / alarm"
/// flow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/features/audio_cutter/data/cutter_math.dart';
import 'package:wavely/features/audio_cutter/data/ringtone_saver.dart';
import 'package:wavely/features/audio_cutter/data/waveform_peaks.dart';
import 'package:wavely/features/audio_cutter/logic/audio_cutter_controller.dart';

/// Route path used by the library selection bar.
const String kAudioCutterRoute = '/library/audio-cutter';

/// Opens the cutter for [sourcePath].
class AudioCutterScreen extends ConsumerStatefulWidget {
  const AudioCutterScreen({required this.sourcePath, super.key});

  final String sourcePath;

  @override
  ConsumerState<AudioCutterScreen> createState() => _AudioCutterScreenState();
}

class _AudioCutterScreenState extends ConsumerState<AudioCutterScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(audioCutterControllerProvider.notifier)
          .load(widget.sourcePath),
    );
  }

  Future<void> _editTimestamp({required bool isStart}) async {
    final AudioCutterState state =
        ref.read(audioCutterControllerProvider);
    final CutSelection? selection = state.selection;
    if (selection == null) {
      return;
    }
    final Duration current = isStart ? selection.start : selection.end;
    final TextEditingController ctrl = TextEditingController(
      text: formatCutTimestamp(current),
    );
    final Duration? parsed = await showDialog<Duration>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(isStart ? 'Start position' : 'End position'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'mm:ss or hh:mm:ss',
            helperText: 'Example: 01:23.500',
          ),
          onSubmitted: (String _) => Navigator.of(dialogContext)
              .pop(parseCutTimestamp(ctrl.text)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(parseCutTimestamp(ctrl.text)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (parsed == null || !mounted) {
      return;
    }
    final CutSelection updated = isStart
        ? clampSelection(parsed, selection.end, state.trackLength)
        : clampSelection(selection.start, parsed, state.trackLength);
    ref
        .read(audioCutterControllerProvider.notifier)
        .updateSelection(updated.start, updated.end);
  }

  Future<void> _cut() async {
    final AudioCutterController controller =
        ref.read(audioCutterControllerProvider.notifier);
    final String? output = await controller.cut();
    if (!mounted) {
      return;
    }
    if (output == null) {
      final String? error = ref.read(audioCutterControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Cut failed')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved: $output')),
    );
  }

  Future<void> _setAs(RingtoneKind kind) async {
    final AudioCutterController controller =
        ref.read(audioCutterControllerProvider.notifier);
    final RingtoneSaveResult? result = await controller.saveAsRingtone(kind);
    if (!mounted) {
      return;
    }
    if (result == null) {
      final String? error = ref.read(audioCutterControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Could not save as ${kind.label}')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved as ${kind.label}: ${result.savedTo}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final AudioCutterState state =
        ref.watch(audioCutterControllerProvider);

    return Scaffold(
      key: const ValueKey<String>('audio-cutter-screen'),
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        title: Text(
          'Audio Cutter',
          style: WavelyTypography.title20(color: colors.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('cutter-save-file'),
            tooltip: 'Save selection as new file',
            icon: const Icon(Icons.save_outlined),
            onPressed: state.phase == CutterPhase.ready ? _cut : null,
          ),
        ],
      ),
      body: switch (state.phase) {
        CutterPhase.idle ||
        CutterPhase.decodingWaveform =>
          const Center(child: CircularProgressIndicator()),
        CutterPhase.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                state.error ?? 'Something went wrong',
                style: WavelyTypography.body14(color: colors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        CutterPhase.ready ||
        CutterPhase.cutting ||
        CutterPhase.savingRingtone =>
          _ReadyBody(
            state: state,
            onEditStart: () => _editTimestamp(isStart: true),
            onEditEnd: () => _editTimestamp(isStart: false),
            onCut: _cut,
            onRingtone: _setAs,
          ),
      },
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.state,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onCut,
    required this.onRingtone,
  });

  final AudioCutterState state;
  final VoidCallback onEditStart;
  final VoidCallback onEditEnd;
  final VoidCallback onCut;
  final ValueChanged<RingtoneKind> onRingtone;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final CutSelection? selection = state.selection;
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              state.sourcePath.split('/').last,
              style: WavelyTypography.caption12(color: colors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.peaks != null && selection != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: SizedBox(
                height: 160,
                child: _WaveformCanvas(
                  peaks: state.peaks!,
                  trackLength: state.trackLength,
                  selection: selection,
                  onSelectionChanged:
                      (Duration start, Duration end) => context
                          .findAncestorStateOfType<
                              ConsumerState<AudioCutterScreen>>()
                          ?.ref
                          .read(audioCutterControllerProvider.notifier)
                          .updateSelection(start, end),
                ),
              ),
            ),
          if (selection != null)
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: <Widget>[
                  _TimestampChip(
                    key: const ValueKey<String>('cutter-start'),
                    label: 'Start',
                    value: formatCutTimestampMs(selection.start),
                    onTap: onEditStart,
                  ),
                  const SizedBox(width: Spacing.sm),
                  _TimestampChip(
                    key: const ValueKey<String>('cutter-length'),
                    label: 'Length',
                    value: formatCutTimestampMs(selection.length),
                    onTap: null,
                  ),
                  const SizedBox(width: Spacing.sm),
                  _TimestampChip(
                    key: const ValueKey<String>('cutter-end'),
                    label: 'End',
                    value: formatCutTimestampMs(selection.end),
                    onTap: onEditEnd,
                  ),
                ],
              ),
            ),
          if (state.phase == CutterPhase.cutting ||
              state.phase == CutterPhase.savingRingtone)
            const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: LinearProgressIndicator(),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('cutter-extract'),
                  onPressed: state.phase == CutterPhase.ready ? onCut : null,
                  icon: const Icon(Icons.content_cut_rounded),
                  label: const Text('Save selection as new file'),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: <Widget>[
                    for (final RingtoneKind kind in RingtoneKind.values) ...<Widget>[
                      Expanded(
                        child: OutlinedButton(
                          key: ValueKey<String>('cutter-ringtone-${kind.name}'),
                          onPressed: state.phase == CutterPhase.ready
                              ? () => onRingtone(kind)
                              : null,
                          child: Text(kind.label),
                        ),
                      ),
                      if (kind != RingtoneKind.alarm)
                        const SizedBox(width: Spacing.sm),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimestampChip extends StatelessWidget {
  const _TimestampChip({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Expanded(
      child: InkWell(
        borderRadius: AppRadii.bMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.elevated,
            borderRadius: AppRadii.bMd,
            border: Border.all(color: colors.borderGlass),
          ),
          child: Column(
            children: <Widget>[
              Text(
                label,
                style: WavelyTypography.caption12(color: colors.textSecondary),
              ),
              Text(
                value,
                style: WavelyTypography.body14Medium(
                  color: onTap == null
                      ? colors.textSecondary
                      : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waveform + selection overlay + edge drag handling.
class _WaveformCanvas extends StatefulWidget {
  const _WaveformCanvas({
    required this.peaks,
    required this.trackLength,
    required this.selection,
    required this.onSelectionChanged,
  });

  final WaveformPeaks peaks;
  final Duration trackLength;
  final CutSelection selection;
  final void Function(Duration start, Duration end) onSelectionChanged;

  @override
  State<_WaveformCanvas> createState() => _WaveformCanvasState();
}

class _WaveformCanvasState extends State<_WaveformCanvas> {
  /// Fraction of the canvas width that acts as a drag handle.
  static const double _handleZoneFraction = 0.18;

  bool _draggingStart = false;
  bool _draggingEnd = false;

  Duration _positionToTime(double x, double width) {
    final double fraction = (x / width).clamp(0.0, 1.0);
    return Duration(
      milliseconds:
          (fraction * widget.trackLength.inMilliseconds).round(),
    );
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    final Duration time =
        _positionToTime(details.localPosition.dx, width);
    if (_draggingStart) {
      widget.onSelectionChanged(time, widget.selection.end);
    } else if (_draggingEnd) {
      widget.onSelectionChanged(widget.selection.start, time);
    }
  }

  void _onTapUp(TapUpDetails details, double width) {
    // Tap near an edge jumps that handle; tap inside selects a centered
    // window of the same length around the tapped point.
    final Duration time =
        _positionToTime(details.localPosition.dx, width);
    final double startFraction =
        widget.selection.start.inMilliseconds /
            widget.trackLength.inMilliseconds;
    final double endFraction =
        widget.selection.end.inMilliseconds /
            widget.trackLength.inMilliseconds;
    if (details.localPosition.dx < width * _handleZoneFraction) {
      widget.onSelectionChanged(time, widget.selection.end);
    } else if (details.localPosition.dx >
        width * (1 - _handleZoneFraction)) {
      widget.onSelectionChanged(widget.selection.start, time);
    } else if (time < widget.selection.start) {
      widget.onSelectionChanged(time, widget.selection.end);
    } else if (time > widget.selection.end) {
      widget.onSelectionChanged(widget.selection.start, time);
    } else {
      // Inside: keep the length, center on the tap.
      final Duration length = widget.selection.length;
      final Duration half = Duration(
        milliseconds: length.inMilliseconds ~/ 2,
      );
      widget.onSelectionChanged(
        time - half,
        time - half + length,
      );
      // Silence unused warnings for fractions (kept for future cursor
      // rendering).
      assert(startFraction <= endFraction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails details) => _onTapUp(details, width),
          onHorizontalDragStart: (DragStartDetails details) {
            final double x = details.localPosition.dx;
            if (x < width * _handleZoneFraction) {
              _draggingStart = true;
            } else if (x > width * (1 - _handleZoneFraction)) {
              _draggingEnd = true;
            }
          },
          onHorizontalDragUpdate: (DragUpdateDetails details) =>
              _onDragUpdate(details, width),
          onHorizontalDragEnd: (_) {
            _draggingStart = false;
            _draggingEnd = false;
          },
          onHorizontalDragCancel: () {
            _draggingStart = false;
            _draggingEnd = false;
          },
          child: CustomPaint(
            size: Size(width, constraints.maxHeight),
            painter: _WaveformPainter(
              peaks: widget.peaks,
              selection: widget.selection,
              trackLength: widget.trackLength,
              waveColor: colors.accentColors.accent,
              dimColor: colors.textTertiary,
              handleColor: colors.textPrimary,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.selection,
    required this.trackLength,
    required this.waveColor,
    required this.dimColor,
    required this.handleColor,
  });

  final WaveformPeaks peaks;
  final CutSelection selection;
  final Duration trackLength;
  final Color waveColor;
  final Color dimColor;
  final Color handleColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (trackLength == Duration.zero || size.width <= 0) {
      return;
    }
    final double width = size.width;
    final double height = size.height;
    final double midY = height / 2;

    final double startFraction =
        selection.start.inMilliseconds / trackLength.inMilliseconds;
    final double endFraction =
        selection.end.inMilliseconds / trackLength.inMilliseconds;
    final double startX = (startFraction * width).clamp(0.0, width);
    final double endX = (endFraction * width).clamp(0.0, width);

    // Dimmed full envelope (background).
    final Paint dimPaint = Paint()
      ..color = dimColor.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    _paintEnvelope(canvas, size, dimPaint, midY);

    // Highlighted selection.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(startX, 0, endX, height));
    final Paint wavePaint = Paint()
      ..color = waveColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    _paintEnvelope(canvas, size, wavePaint, midY);
    canvas.restore();

    // Selection border + handles.
    final Paint borderPaint = Paint()
      ..color = waveColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTRB(startX, 2, endX, height - 2),
      borderPaint,
    );
    final Paint handlePaint = Paint()..color = handleColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(startX - 2.5, height * 0.2, startX + 2.5, height * 0.8),
        const Radius.circular(3),
      ),
      handlePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(endX - 2.5, height * 0.2, endX + 2.5, height * 0.8),
        const Radius.circular(3),
      ),
      handlePaint,
    );
  }

  void _paintEnvelope(Canvas canvas, Size size, Paint paint, double midY) {
    final int buckets = peaks.length;
    if (buckets == 0) {
      return;
    }
    final double width = size.width;
    final Path path = Path();
    for (var i = 0; i < buckets; i++) {
      final double x = (i / buckets) * width;
      final double halfHeight = peaks.peakAt(i) * (size.height / 2 - 2);
      path.moveTo(x, midY - halfHeight);
      path.lineTo(x, midY + halfHeight);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.peaks != peaks ||
      oldDelegate.selection != selection ||
      oldDelegate.trackLength != trackLength;
}
