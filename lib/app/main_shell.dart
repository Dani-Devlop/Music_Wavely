import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/desktop_shell.dart';
import 'package:wavely/app/layout_breakpoints.dart';
import 'package:wavely/core/constants/app_constants.dart' show AppConstants;
import 'package:wavely/data/sync/sync_providers.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/player/data/adaptive_accent_service.dart';
import 'package:wavely/features/player/presentation/mini_player_widget.dart';
import 'package:wavely/features/settings/data/update_providers.dart';
import 'package:wavely/features/settings/presentation/whats_new.dart';
import 'package:wavely/features/web/ios_guidance_banner.dart';
import 'package:wavely/playback/queue/queue_manager.dart';
import 'package:wavely/playback/widgets/widget_sync.dart';

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

/// Main app shell — PLATFORM-ADAPTIVE (v1.0.2 owner spec):
///
/// - **width < 800** → the MOBILE shell: body (stateful shell branch) +
///   mini player + floating glass bottom navigation with exactly FOUR
///   destinations (Playlist | Now Playing | Search | Settings) and a
///   glowing active icon — the Musicolet-style Android experience.
/// - **width >= 800** → [DesktopShell], the Spotify-style three-column
///   desktop layout with the fixed glass bottom playbar.
///
/// v1.0.1-beta3 parity note: the former Local and Online tabs live inside
/// the Search tab (see SearchHubShell); the second tab is the full player.
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
    // Phase 9: activate the home-widget / QS-tile state publisher (Android
    // only — the provider no-ops elsewhere). Reading it once keeps the
    // keepAlive subscription alive for the process lifetime.
    ref.read(widgetSyncProvider);
    // Phase 10.1: adaptive accent extraction (no-op unless enabled).
    ref.read(adaptiveAccentServiceProvider);
    // Phase 10.4: What's New sheet on version change (post-frame so the
    // context is attached; hermetic under flutter test — the sheet is a
    // plain modal, but package_info resolves from the static mock).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_maybeShowWhatsNew(context));
    });
  }

  /// Phase 10.4: shows the changelog sheet once per version.
  Future<void> _maybeShowWhatsNew(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) {
        return;
      }
      await maybeShowWhatsNew(context, prefs, info.version);
    } on Object {
      // package_info unavailable (tests / exotic platforms) — skip.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Platform-adaptive split (owner spec: < 800 px → Musicolet-style
    // Android layout; >= 800 px → Spotify-style desktop layout).
    if (isDesktopLayout(MediaQuery.sizeOf(context).width)) {
      return DesktopShell(navigationShell: widget.navigationShell);
    }
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

/// The floating, heavily-blurred glass bottom navigation bar — exactly
/// four destinations (owner parity spec).
class _FloatingGlassNav extends ConsumerWidget {
  const _FloatingGlassNav({required this.navigationShell});

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(label: 'Playlist', icon: Icons.playlist_play_rounded),
    _NavDestination(label: 'Now Playing', icon: Icons.album_rounded),
    _NavDestination(label: 'Search', icon: Icons.search_rounded),
    _NavDestination(label: 'Settings', icon: Icons.settings_rounded),
  ];

  /// Index of the Settings destination (badge host for update notices).
  static const int _settingsTabIndex = 3;

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  child: _navButton(context, ref, _destinations[i], i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navButton(
    BuildContext context,
    WidgetRef ref,
    _NavDestination destination,
    int index,
  ) {
    final colors = context.wavelyColors;
    final selected = index == navigationShell.currentIndex;
    final accent = colors.accentColors.accent;
    final color = selected ? accent : colors.textSecondary;
    // Stage 7: subtle dot on the Settings tab while a newer release is
    // published (one-shot background check, hermetic under flutter test).
    final showUpdateBadge = index == _settingsTabIndex &&
        (ref.watch(updateAvailableBadgeProvider).value ?? false);
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
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(destination.icon, color: color, size: 22),
                      if (showUpdateBadge)
                        Positioned(
                          top: -1,
                          right: -3,
                          child: Container(
                            key: const Key('nav-update-badge'),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colors.accentColors.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.bgBase,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
