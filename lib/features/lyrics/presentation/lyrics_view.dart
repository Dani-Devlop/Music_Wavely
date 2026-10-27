import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/extensions.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/lyrics/data/lyrics_repository.dart';
import 'package:wavely/features/lyrics/domain/lyrics_sync_controller.dart';

/// Loads and keeps the [LyricsResult] for a track (repository-backed).
///
/// Keyed by [Track] (freezed equality) so equal tracks share state and
/// `ref.invalidate(lyricsFutureProvider(track))` reloads one track.
final lyricsFutureProvider =
    FutureProvider.family<LyricsResult?, Track>((ref, track) {
  return ref.watch(lyricsRepositoryProvider).fetch(track);
});

/// User-adjusted lyric offset (ms) read from the lyrics cache port.
final lyricsOffsetProvider =
    FutureProvider.family<int, int>((ref, trackId) async {
  final row = await ref.watch(lyricsCacheProvider).get(trackId: trackId);
  return row?.offsetMs ?? 0;
});

/// Synced/plain lyric renderer with auto-scroll, tap-to-seek and a
/// user-adjustable offset sheet.
///
/// Display semantics: the user offset follows the LRC `offset:` tag
/// convention — displayed time = line.startTime - offsetMs, so a POSITIVE
/// stored offset shows lyrics EARLIER. The '+0.5 s' sheet button therefore
/// DECREASES the stored offset (shifts lyrics later), and vice versa.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({
    required this.track,
    required this.positionStream,
    required this.onSeek,
    this.height,
    super.key,
  });

  final Track track;
  final Stream<Duration> positionStream;
  final Future<void> Function(Duration) onSeek;
  final double? height;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  static const int _offsetStepMs = 500;
  static const double _edgePaddingFactor = 0.4;
  static const double _emptyLineGap = 24;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};

  LyricsSyncController? _sync;
  StreamSubscription<int>? _activeSub;
  LyricsResult? _cachedResult;
  int _cachedOffset = -1;
  List<LyricLine>? _effectiveLines;
  int _activeIndex = -1;
  bool _userScrolling = false;
  Timer? _resumeTimer;

  @override
  void dispose() {
    _resumeTimer?.cancel();
    unawaited(_activeSub?.cancel());
    _sync?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(lyricsFutureProvider(widget.track));
    final trackId = widget.track.id;
    final offset = trackId == null
        ? 0
        : ref.watch(lyricsOffsetProvider(trackId)).value ?? 0;
    final content = resultAsync.when(
      loading: () => const Center(child: ProgressRing()),
      error: (_, __) => ErrorState(
        message: 'Could not load lyrics',
        detail: 'Check the track file or try again.',
        onRetry: () => ref.invalidate(lyricsFutureProvider(widget.track)),
      ),
      data: (result) {
        if (result == null || result.lines.isEmpty) {
          return const EmptyState(
            icon: Icons.lyrics_outlined,
            title: 'No lyrics for this track',
          );
        }
        if (!result.synced) {
          return _buildPlain(context, result);
        }
        return _buildSynced(context, result, offset);
      },
    );
    final height = widget.height;
    if (height != null) {
      return SizedBox(height: height, child: content);
    }
    return content;
  }

  // -- plain (unsynced) ----------------------------------------------------

  Widget _buildPlain(BuildContext context, LyricsResult result) {
    final colors = context.wavelyColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Text(
        result.lines.map((line) => line.text).join('\n'),
        style: WavelyTypography.body14(color: colors.textSecondary),
      ),
    );
  }

  // -- synced ---------------------------------------------------------------

  Widget _buildSynced(BuildContext context, LyricsResult result, int offset) {
    final colors = context.wavelyColors;
    final lines = _resolveEffectiveLines(result, offset);
    _ensureSync(lines);
    final viewport =
        widget.height ?? MediaQuery.sizeOf(context).height;
    return Column(
      children: <Widget>[
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onUserScroll,
            child: ListView.builder(
              key: _listKey,
              controller: _scrollController,
              padding: EdgeInsets.symmetric(
                vertical: viewport * _edgePaddingFactor,
              ),
              itemCount: lines.length,
              itemBuilder: (context, index) =>
                  _buildLine(context, colors, lines, index),
            ),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(_showOffsetSheet()),
          child: const Text('Adjust offset'),
        ),
      ],
    );
  }

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.direction != ScrollDirection.idle) {
      _pauseAutoScroll();
    }
    return false;
  }

  Widget _buildLine(
    BuildContext context,
    WavelySemanticColors colors,
    List<LyricLine> lines,
    int index,
  ) {
    final line = lines[index];
    final isCurrent = index == _activeIndex;
    if (line.text.isEmpty) {
      // Kept as gaps; never scroll targets (no key, no tap handler).
      return const SizedBox(height: _emptyLineGap);
    }
    final key = _lineKeys.putIfAbsent(index, GlobalKey.new);
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(widget.onSeek(line.startTime)),
      child: Semantics(
        button: true,
        label: 'Seek to ${line.startTime.hm}: ${line.text}',
        child: AnimatedOpacity(
          duration: WavelyDurations.normal,
          opacity:
              isCurrent ? 1 : AppConstants.lyricsNeighborOpacity,
          child: AnimatedScale(
            duration: WavelyDurations.normal,
            alignment: AlignmentDirectional.centerStart,
            scale:
                isCurrent ? AppConstants.lyricsCurrentLineScale : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.sm,
              ),
              child: Text(
                line.text,
                style: WavelyTypography.body14Medium(
                  color: isCurrent
                      ? colors.accentColors.accent
                      : colors.textSecondary,
                ).copyWith(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- offset handling ------------------------------------------------------

  List<LyricLine> _resolveEffectiveLines(
    LyricsResult result,
    int offsetMs,
  ) {
    if (identical(_cachedResult, result) &&
        _cachedOffset == offsetMs &&
        _effectiveLines != null) {
      return _effectiveLines!;
    }
    final lines = offsetMs == 0
        ? result.lines
        : <LyricLine>[
            for (final line in result.lines)
              line.copyWith(
                startTime: Duration(
                  milliseconds: math.max(
                    0,
                    line.startTime.inMilliseconds - offsetMs,
                  ),
                ),
              ),
          ];
    _cachedResult = result;
    _cachedOffset = offsetMs;
    _effectiveLines = lines;
    return lines;
  }

  Future<void> _showOffsetSheet() async {
    final trackId = widget.track.id;
    if (trackId == null) {
      return;
    }
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Adjust offset', style: WavelyTypography.title18()),
              const SizedBox(height: Spacing.sm),
              Text(
                'Lyrics late? Nudge them. Displayed time = stamped time '
                '- offset.',
                style: WavelyTypography.caption12(
                  color: context.wavelyColors.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  OutlinedButton(
                    // Offset decreases -> lyrics display LATER.
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(-_offsetStepMs),
                    child: const Text('+0.5 s'),
                  ),
                  OutlinedButton(
                    // Offset increases -> lyrics display EARLIER.
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(_offsetStepMs),
                    child: const Text('-0.5 s'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(0),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    final current = ref.read(lyricsOffsetProvider(trackId)).value ?? 0;
    final next = choice == 0 ? 0 : current + choice;
    await ref
        .read(lyricsCacheProvider)
        .updateOffset(trackId: trackId, offsetMs: next);
    if (!mounted) {
      return;
    }
    ref.invalidate(lyricsOffsetProvider(trackId));
  }

  // -- sync + auto-scroll ---------------------------------------------------

  void _ensureSync(List<LyricLine> lines) {
    final existing = _sync;
    if (existing != null && identical(_effectiveLines, lines)) {
      return;
    }
    _resumeTimer?.cancel();
    unawaited(_activeSub?.cancel());
    existing?.dispose();
    final controller = LyricsSyncController(
      lines: lines,
      positionStream: widget.positionStream,
    );
    _sync = controller;
    _activeIndex = -1;
    _activeSub = controller.activeLineStream.listen((index) {
      if (!mounted) {
        return;
      }
      setState(() => _activeIndex = index);
      _scrollToLine(index);
    });
  }

  void _pauseAutoScroll() {
    _userScrolling = true;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(
      const Duration(
        seconds: AppConstants.lyricsAutoScrollResumeDelaySeconds,
      ),
      () => _userScrolling = false,
    );
  }

  void _scrollToLine(int index) {
    if (index < 0 || _userScrolling) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final lineContext = _lineKeys[index]?.currentContext;
      final listContext = _listKey.currentContext;
      if (lineContext == null || listContext == null) {
        return;
      }
      final lineBox = lineContext.findRenderObject() as RenderBox?;
      final listBox = listContext.findRenderObject() as RenderBox?;
      if (lineBox == null ||
          listBox == null ||
          !lineBox.attached ||
          !lineBox.hasSize) {
        return;
      }
      final lineTop = lineBox.localToGlobal(Offset.zero).dy;
      final listTop = listBox.localToGlobal(Offset.zero).dy;
      final viewport = listBox.size.height;
      final target = _scrollController.offset +
          lineTop -
          listTop -
          viewport / 2 +
          lineBox.size.height / 2;
      final clamped = target
          .clamp(0.0, _scrollController.position.maxScrollExtent)
          .toDouble();
      unawaited(
        _scrollController.animateTo(
          clamped,
          duration: WavelyDurations.normal,
          curve: WavelyDurations.standard,
        ),
      );
    });
  }
}
