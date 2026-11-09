/// The DESKTOP shell — a premium Spotify clone (v1.0.2, width >= 800).
///
/// Owner spec, implemented verbatim:
/// - **3-column layout**: left sidebar (250 px: logo, Home, Search,
///   Library, Playlists on a dark gradient), center main view (the routed
///   branch content: hero, "Made for you" carousels, album grid) and a
///   right sidebar (300 px: Now Playing details + Next in queue).
/// - **Bottom playbar**: full-width, fixed: album art, transport controls,
///   seekbar, volume and the device selector. Glassmorphism throughout.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/extensions/duration_x.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/design_system/components/wavely_cover_widget.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/library/data/library_view_config.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';
import 'package:wavely/features/library/presentation/library_tab_manager.dart';
import 'package:wavely/features/player/presentation/now_playing_screen.dart';
import 'package:wavely/features/player/presentation/queue_manager_sheet.dart';
import 'package:wavely/features/search/presentation/search_screen.dart';
import 'package:wavely/features/settings/presentation/settings_screen.dart';
import 'package:wavely/playback/engines/engine_factory.dart';
import 'package:wavely/playback/engines/playback_engine.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// Glass blur used by the playbar (heavy — it floats over content).
const double _playbarBlurSigma = 26;

/// Fixed widths of the three columns (owner spec: 250 / flexible / 300).
const double _sidebarWidth = 250;
const double _rightPanelWidth = 300;

/// The Spotify-style desktop shell around the stateful navigation shell.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  bool _playlistsSelected = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Sidebar(
                    playlistsSelected: _playlistsSelected,
                    onNavigate: (route) {
                      setState(() {
                        _playlistsSelected =
                            route == LibraryScreen.libraryRoute &&
                                ref.read(pendingLibraryTabProvider) ==
                                    LibraryTabId.playlists;
                      });
                      context.go(route);
                    },
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: widget.navigationShell,
                    ),
                  ),
                  const _RightPanel(),
                ],
              ),
            ),
            const _DesktopPlaybar(),
          ],
        ),
      ),
    );
  }
}

// -- LEFT SIDEBAR --------------------------------------------------------------

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.playlistsSelected,
    required this.onNavigate,
  });

  /// Whether the Playlists entry is the visually-selected nav item (the
  /// router cannot know which library tab is active, so the shell tracks
  /// the last sidebar tap).
  final bool playlistsSelected;

  /// Invoked with the target route; the shell updates its sidebar
  /// selection state before navigating.
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final location = GoRouterState.of(context).matchedLocation;
    final inLibrary = location.startsWith(LibraryScreen.libraryRoute);
    return Container(
      width: _sidebarWidth,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colors.elevated.withValues(alpha: 0.9),
            colors.bgBase.withValues(alpha: 0.6),
          ],
        ),
        border: Border(
          right: BorderSide(color: colors.borderGlass),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // -- brand ---------------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.md,
            ),
            child: Row(
              children: <Widget>[
                const WavelyLogo(size: 30),
                const SizedBox(width: Spacing.md),
                Text(
                  'Wavely',
                  style: WavelyTypography.title18(color: colors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          // -- primary nav ----------------------------------------------
          _SideNavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            selected: !inLibrary && location.startsWith('/home'),
            onTap: () => onNavigate('/home'),
          ),
          _SideNavItem(
            icon: Icons.search_rounded,
            label: 'Search',
            selected: location.startsWith('/search'),
            onTap: () => onNavigate(SearchScreen.route),
          ),
          _SideNavItem(
            icon: Icons.library_music_rounded,
            label: 'Library',
            selected: inLibrary && !playlistsSelected,
            onTap: () {
              ref.read(pendingLibraryTabProvider.notifier).state = null;
              onNavigate(LibraryScreen.libraryRoute);
            },
          ),
          _SideNavItem(
            icon: Icons.playlist_play_rounded,
            label: 'Playlists',
            selected: playlistsSelected,
            onTap: () {
              ref.read(pendingLibraryTabProvider.notifier).state =
                  LibraryTabId.playlists;
              onNavigate(LibraryScreen.libraryRoute);
            },
          ),
          const Spacer(),
          const Divider(color: Colors.white12, height: 1),
          _SideNavItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            selected: location.startsWith(SettingsScreen.route),
            onTap: () => onNavigate(SettingsScreen.route),
          ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.bMd,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadii.bMd,
            color: selected ? Colors.white.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 22,
                color: selected ? accent : colors.textSecondary,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WavelyTypography.body14Medium(
                    color: selected ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- RIGHT PANEL ---------------------------------------------------------------

class _RightPanel extends ConsumerWidget {
  const _RightPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final queue = ref.watch(queueManagerProvider);
    final track = queue.currentTrack;
    return Container(
      width: _rightPanelWidth,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colors.elevated.withValues(alpha: 0.9),
            colors.bgBase.withValues(alpha: 0.6),
          ],
        ),
        border: Border(
          left: BorderSide(color: colors.borderGlass),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Now playing',
                  style: WavelyTypography.title18(color: colors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Open full player',
                icon: Icon(Icons.open_in_full_rounded,
                    size: 18, color: colors.textSecondary),
                onPressed: () =>
                    unawaited(context.push(NowPlayingScreen.route)),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (track == null)
            Expanded(
              child: Center(
                child: Text(
                  'Nothing playing',
                  style: WavelyTypography.body14(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            )
          else ...<Widget>[
            // -- cover + details ----------------------------------------
            AspectRatio(
              aspectRatio: 1,
              child: WavelyCover(
                label: track.title,
                coverPath: track.coverPath,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WavelyTypography.title18(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              track.artistOrUnknown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WavelyTypography.body14(color: colors.textSecondary),
            ),
            if (track.album?.isNotEmpty == true)
              Text(
                track.album!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WavelyTypography.caption12(color: colors.textTertiary),
              ),
            const SizedBox(height: Spacing.lg),
            // -- next in queue ------------------------------------------
            Text(
              'Next in queue',
              style: WavelyTypography.title18(color: colors.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(child: _NextInQueue(queue: queue)),
          ],
        ],
      ),
    );
  }
}

class _NextInQueue extends ConsumerWidget {
  const _NextInQueue({required this.queue});

  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final upcoming = <Track>[
      for (var i = queue.currentIndex + 1;
          i < queue.tracks.length && i < queue.currentIndex + 20;
          i++)
        queue.tracks[i],
    ];
    if (upcoming.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: WavelyTypography.caption12(color: colors.textTertiary),
        ),
      );
    }
    return ListView.builder(
      itemCount: upcoming.length,
      itemBuilder: (context, index) {
        final track = upcoming[index];
        final absoluteIndex = queue.currentIndex + 1 + index;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 40,
            height: 40,
            child: WavelyCover(
              label: track.title,
              coverPath: track.coverPath,
            ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                WavelyTypography.body14Medium(color: colors.textPrimary),
          ),
          subtitle: Text(
            track.artistOrUnknown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WavelyTypography.caption12(color: colors.textSecondary),
          ),
          trailing: Text(
            track.displayDuration,
            style: WavelyTypography.timerTabular(color: colors.textTertiary),
          ),
          onTap: () => unawaited(
            ref
                .read(queueManagerProvider.notifier)
                .setQueue(List<Track>.of(queue.tracks),
                    startIndex: absoluteIndex),
          ),
        );
      },
    );
  }
}

// -- BOTTOM PLAYBAR -------------------------------------------------------------

class _DesktopPlaybar extends ConsumerStatefulWidget {
  const _DesktopPlaybar();

  @override
  ConsumerState<_DesktopPlaybar> createState() => _DesktopPlaybarState();
}

class _DesktopPlaybarState extends ConsumerState<_DesktopPlaybar> {
  double _volume = 1;

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    final PlaybackEngine engine = ref.read(playbackEngineProvider);
    await engine.setVolume(value);
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(queueManagerProvider.notifier);
    final queue = ref.watch(queueManagerProvider);
    final engineState = ref.watch(audioEngineControllerProvider);
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    final track = queue.currentTrack;
    final isPlaying = queue.playbackState == PlaybackState.playing;
    final durationMs = queue.duration.inMilliseconds;
    final positionMs = queue.position.inMilliseconds;
    final seekValue = durationMs <= 0
        ? 0.0
        : (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
    final minTarget = BoxConstraints(
      minWidth: AppConstants.touchTargetMin,
      minHeight: AppConstants.touchTargetMin,
    );
    return GlassCard(
      blurSigma: _playbarBlurSigma,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.borderGlass)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg, vertical: Spacing.sm,
        ),
        child: Row(
          children: <Widget>[
            // -- left: art + meta --------------------------------------
            SizedBox(
              width: 220,
              child: track == null
                  ? Text(
                      'Nothing playing',
                      style: WavelyTypography.body14(
                        color: colors.textSecondary,
                      ),
                    )
                  : Row(
                      children: <Widget>[
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: WavelyCover(
                            label: track.title,
                            coverPath: track.coverPath,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WavelyTypography.body14Medium(
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                track.artistOrUnknown,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WavelyTypography.caption12(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            // -- center: controls + seekbar ------------------------------
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconButton(
                        constraints: minTarget,
                        tooltip: 'Shuffle',
                        onPressed: () =>
                            unawaited(manager.toggleShuffle()),
                        color: queue.shuffleEnabled
                            ? accent
                            : colors.textSecondary,
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                      ),
                      IconButton(
                        constraints: minTarget,
                        tooltip: 'Previous',
                        onPressed: () => unawaited(manager.previous()),
                        color: colors.textPrimary,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: colors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          constraints: minTarget,
                          tooltip: 'Play or pause',
                          onPressed: () =>
                              unawaited(manager.togglePlayPause()),
                          color: colors.bgBase,
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                      IconButton(
                        constraints: minTarget,
                        tooltip: 'Next',
                        onPressed: () => unawaited(manager.next()),
                        color: colors.textPrimary,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                      IconButton(
                        constraints: minTarget,
                        tooltip: 'Repeat',
                        onPressed: () => manager.setRepeatMode(
                          switch (queue.repeatMode) {
                            RepeatMode.off => RepeatMode.all,
                            RepeatMode.all => RepeatMode.one,
                            RepeatMode.one => RepeatMode.off,
                          },
                        ),
                        color: queue.repeatMode == RepeatMode.off
                            ? colors.textSecondary
                            : accent,
                        icon: Icon(
                          queue.repeatMode == RepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 26,
                    child: Row(
                      children: <Widget>[
                        Text(
                          queue.position.hm,
                          style: WavelyTypography.micro10(
                            color: colors.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                            ),
                            child: Slider(
                              value: seekValue,
                              activeColor: accent,
                              inactiveColor: colors.borderGlass,
                              onChanged: durationMs <= 0
                                  ? null
                                  : (v) => unawaited(
                                        manager.seek(
                                          Duration(
                                            milliseconds:
                                                (v * durationMs).round(),
                                          ),
                                        ),
                                      ),
                            ),
                          ),
                        ),
                        Text(
                          queue.duration.hm,
                          style: WavelyTypography.micro10(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // -- right: queue · device · volume --------------------------
            SizedBox(
              width: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    constraints: minTarget,
                    tooltip: 'Queue manager',
                    onPressed: () =>
                        unawaited(showQueueManagerSheet(context)),
                    color: colors.textSecondary,
                    icon: const Icon(Icons.queue_music_rounded, size: 20),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Output device',
                    icon: Icon(Icons.speaker_rounded,
                        size: 20, color: colors.textSecondary),
                    onSelected: (_) {},
                    itemBuilder: (context) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        enabled: false,
                        value: 'current',
                        child: Text(
                          'Output: ${engineState.outputDeviceLabel}',
                          style: WavelyTypography.caption12(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        enabled: false,
                        value: 'default',
                        child: Text(
                          'System default is applied per output device '
                          'profile.',
                          style: WavelyTypography.micro10(
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: Spacing.sm),
                  Icon(Icons.volume_up_rounded,
                      size: 20, color: colors.textSecondary),
                  SizedBox(
                    width: 90,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        value: _volume,
                        activeColor: accent,
                        inactiveColor: colors.borderGlass,
                        onChanged: (v) => unawaited(_setVolume(v)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
