import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';

/// v1.0.1-beta3: the Search tab hosts the whole "find things" surface.
///
/// The former Local and Online bottom tabs now live INSIDE the Search
/// branch (owner spec: exactly four bottom tabs — Playlist / Now Playing /
/// Search / Settings). This shell renders a persistent chip row
/// (Search · Library · Online) above the active pane and switches between
/// `/search`, `/local` and `/online` within the same shell branch, so each
/// pane keeps its own state and scroll position.
class SearchHubShell extends StatelessWidget {
  /// Wraps the routed [child] with the hub chip row.
  const SearchHubShell({required this.child, required this.location, super.key});

  final Widget child;

  /// Current matched location (decides the active chip).
  final String location;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  _hubChip(
                    context,
                    key: const Key('hub-chip-search'),
                    icon: Icons.search_rounded,
                    label: 'Search',
                    route: '/search',
                    active: location.startsWith('/search'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  _hubChip(
                    context,
                    key: const Key('hub-chip-local'),
                    icon: Icons.library_music_rounded,
                    label: 'Library',
                    route: '/local',
                    active: location.startsWith('/local'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  _hubChip(
                    context,
                    key: const Key('hub-chip-online'),
                    icon: Icons.explore_rounded,
                    label: 'Online',
                    route: '/online',
                    active: location.startsWith('/online'),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _hubChip(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required String route,
    required bool active,
  }) {
    final colors = context.wavelyColors;
    final accent = colors.accentColors.accent;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        key: key,
        borderRadius: AppRadii.bXl,
        onTap: route == location ? null : () => GoRouter.of(context).go(route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.16) : colors.surface,
            borderRadius: AppRadii.bXl,
            border: Border.all(
              color: active ? accent : colors.borderGlass,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: active ? accent : colors.textSecondary,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                label,
                style: WavelyTypography.body14Medium(
                  color: active ? accent : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
