import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/data/sync/sync_providers.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/player/presentation/mini_player_widget.dart';
import 'package:wavely/features/web/ios_guidance_banner.dart';
import 'package:wavely/playback/queue/queue_manager.dart';

/// One bottom-navigation destination of the app shell.
class _NavDestination {
  const _NavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Height of each nav button row (logical px; comfortably above the 44dp
/// minimum touch target — AppConstants.touchTargetMin).
const double _navButtonHeight = 56;

/// Main app shell: body (stateful shell branch) + mini player + glass bottom
/// navigation. Backdrop-filter budget: one GlassCard for the bar plus the
/// mini player's own card — within [AppConstants.maxBackdropFiltersPerScreen].
class MainShell extends ConsumerStatefulWidget {
  /// Creates the shell around [navigationShell].
  const MainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}
class _MainShellState extends ConsumerState<MainShell> {
  static bool _syncStarted = false;

  @override
  void initState() {
    super.initState();
    // Stage 1.2 (B4): kick the sync engine once per process. Without
    // SUPABASE_* keys the service idles in `SyncStatus.disabled` (start() is
    // a no-op); tests never reach this path because they pump screens
    // directly. connectivity_plus 7.x emits List<ConnectivityResult>.
    if (!_syncStarted) {
      _syncStarted = true;
      unawaited(
        ref.read(syncServiceProvider).start(
              connectivityChanges: Connectivity()
                  .onConnectivityChanged
                  .map((statuses) => !statuses.contains(ConnectivityResult.none)),
            ),
      );
    }
    // Stage 2.2: iOS PWA background-audio guidance (web+iOS only,
    // dismissible, persisted) — a complete no-op on every other platform.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(maybeShowIosGuidanceBanner(context, ref));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasTrack = ref.watch(
      queueManagerProvider.select((state) => state.currentTrack != null),
    );
    return Scaffold(
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasTrack) const MiniPlayerWidget(),
          _GlassBottomNav(navigationShell: widget.navigationShell),
        ],
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  const _GlassBottomNav({required this.navigationShell});

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(label: 'Library', icon: Icons.library_music_rounded),
    _NavDestination(label: 'Search', icon: Icons.search_rounded),
    _NavDestination(label: 'Settings', icon: Icons.settings_rounded),
  ];

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.xs,
          Spacing.md,
          Spacing.sm,
        ),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: _navButton(
                    colors,
                    _destinations[i],
                    i,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(
    WavelySemanticColors colors,
    _NavDestination destination,
    int index,
  ) {
    final selected = index == navigationShell.currentIndex;
    final color = selected ? colors.accentColors.accent : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        borderRadius: AppRadii.bMd,
        onTap: () => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        child: SizedBox(
          height: _navButtonHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(destination.icon, color: color),
              const SizedBox(height: Spacing.xs),
              Text(
                destination.label,
                style: WavelyTypography.caption12(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
