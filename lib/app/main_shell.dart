import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/core/constants/app_constants.dart' show AppConstants;
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

/// Heavy backdrop blur for the floating nav bar ("2026 look"): stronger
/// than the elevated surface budget on purpose — the bar floats over
/// content and must stay legible over album art.
const double _navBlurSigma = 26;

/// Main app shell: body (stateful shell branch) + mini player + floating
/// glass bottom navigation with five destinations (Home | Local | Online |
/// Search | Settings) and a glowing active icon.
///
/// Backdrop-filter budget: one GlassCard for the bar plus the mini player's
/// own card — within [AppConstants.maxBackdropFiltersPerScreen].
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
          _FloatingGlassNav(navigationShell: widget.navigationShell),
        ],
      ),
    );
  }
}

/// The floating, heavily-blurred glass bottom navigation bar.
class _FloatingGlassNav extends StatelessWidget {
  const _FloatingGlassNav({required this.navigationShell});

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(label: 'Home', icon: Icons.home_rounded),
    _NavDestination(label: 'Local', icon: Icons.library_music_rounded),
    _NavDestination(label: 'Online', icon: Icons.explore_rounded),
    _NavDestination(label: 'Search', icon: Icons.search_rounded),
    _NavDestination(label: 'Settings', icon: Icons.settings_rounded),
  ];

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.sm,
        ),
        child: GlassCard(
          blurSigma: _navBlurSigma,
          borderRadius: AppRadii.bXl,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _destinations.length; i++)
                Expanded(
                  child: _navButton(context, _destinations[i], i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(
    BuildContext context,
    _NavDestination destination,
    int index,
  ) {
    final colors = context.wavelyColors;
    final selected = index == navigationShell.currentIndex;
    final accent = colors.accentColors.accent;
    final color = selected ? accent : colors.textSecondary;
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
              // Glowing active icon: an accent halo blooms behind the glyph
              // (and fades out for inactive tabs) via implicit animation.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: accent.withValues(alpha: 0.55),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: AnimatedScale(
                  scale: selected ? 1.12 : 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(destination.icon, color: color, size: 22),
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                destination.label,
                style: WavelyTypography.caption12(
                  color: selected ? accent : colors.textSecondary,
                ),
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
