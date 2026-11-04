import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/ai_chat/presentation/ai_chat_screen.dart';
import 'package:wavely/features/discovery/presentation/discovery_screen.dart';
import 'package:wavely/features/search/presentation/online_search_pane.dart';
import 'package:wavely/features/settings/presentation/widgets/subsonic_config_sheet.dart';

/// Section header caption above the unified online search box.
const String _searchHint = 'Search Jamendo, FMA, Archive.org and Subsonic';

/// Online tab: the legal-source side of Wavely — Discovery, Subsonic
/// (Navidrome) sources, the unified online search over every enabled
/// source (Jamendo / FMA / Archive.org / Subsonic) and the AI assistant.
///
/// BackdropFilter budget: the hero cards are SOLID containers (surface
/// tint + borderGlass), deliberately NOT GlassCards, so this screen renders
/// zero blur layers (AppConstants.maxBackdropFiltersPerScreen).
class OnlineScreen extends ConsumerStatefulWidget {
  /// Creates the online screen.
  const OnlineScreen({super.key});

  /// Route path for the app router's online branch.
  static const String route = '/online';

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    ref.read(onlineSearchControllerProvider.notifier).onQueryChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Online',
                    style: WavelyTypography.display24(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Legal sources, discovery and your self-hosted library.',
                    style: WavelyTypography.body14(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SourceCard(
                      colors: colors,
                      icon: Icons.explore_rounded,
                      title: 'Discovery',
                      subtitle: 'Releases from artists you follow',
                      onTap: () =>
                          GoRouter.of(context).push(DiscoveryScreen.route),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: _SourceCard(
                      colors: colors,
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI search',
                      subtitle: 'Ask, queue and mood-match',
                      onTap: () => GoRouter.of(context).push(AiChatScreen.route),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: _SourceCard(
                colors: colors,
                icon: Icons.dns_rounded,
                title: 'Subsonic / Navidrome',
                subtitle: 'Connect a self-hosted music server',
                onTap: () => unawaited(_openSubsonicConfig(context)),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            const SectionHeader(title: 'Search the sources'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                0,
              ),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: _searchHint,
                  prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: colors.textTertiary),
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            const SizedBox(height: 420, child: OnlineSearchPane()),
          ],
        ),
      ),
    );
  }

  Future<void> _openSubsonicConfig(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => const SubsonicConfigSheet(),
    );
  }
}

/// Solid (no-blur) source entry card.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final WavelySemanticColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = colors.accentColors;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        borderRadius: AppRadii.bLg,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.bLg,
            border: Border.all(color: colors.borderGlass),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: AppRadii.bMd,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[accent.accent, accent.gradientStart],
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: WavelyTypography.body14Medium(
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: WavelyTypography.caption12(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
