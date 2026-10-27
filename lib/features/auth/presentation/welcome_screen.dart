import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/data/remote/supabase_client_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/auth/presentation/auth_disabled.dart';
import 'package:wavely/features/auth/presentation/login_screen.dart';
import 'package:wavely/features/library/presentation/library_screen.dart';

/// Welcome / hero screen (Stage 1.2, task B3).
///
/// Solid token-styled containers only — deliberately NOT [GlassCard], so no
/// BackdropFilter is spent here (see the settings screen rationale: the
/// per-screen blur budget is [AppConstants.maxBackdropFiltersPerScreen]).
class WelcomeScreen extends ConsumerWidget {
  /// Creates the welcome screen.
  const WelcomeScreen({super.key});

  /// Route path for the orchestrator's router wiring.
  static const String route = '/welcome';

  void _continueWithoutAccount(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(LibraryScreen.libraryRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final authEnabled = ref.watch(authEnabledProvider);
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: authEnabled
              ? _buildHero(context, colors)
              : AuthDisabledView(
                  onBack: () => _continueWithoutAccount(context),
                  ctaLabel: 'Continue — local only',
                ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, WavelySemanticColors colors) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(Spacing.xl),
            decoration: BoxDecoration(
              color: colors.elevated,
              borderRadius: AppRadii.bXl,
              border: Border.all(color: colors.borderGlass),
            ),
            child: Column(
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        colors.accentColors.accent.withValues(alpha: 0.12),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 36,
                    color: colors.accentColors.accent,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  'Wavely',
                  style: WavelyTypography.display32(
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Your music. Your device. Private by default.',
                  style: WavelyTypography.body14(
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Crash reports only — no analytics, no PII',
                  style: WavelyTypography.caption12(
                    color: colors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => context.push(LoginScreen.route),
            child: const Text('Sign in'),
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton(
            onPressed: () => _continueWithoutAccount(context),
            child: const Text('Continue — local only'),
          ),
        ],
      );
}
