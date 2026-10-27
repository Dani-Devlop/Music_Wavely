import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:wavely/design_system/design_system.dart';

/// Auth-disabled placeholder rendered by every auth screen when Supabase is
/// not configured (B3: never crash when the dart-defines are absent).
///
/// The B3 spec string 'Sign-in is disabled — SUPABASE_URL not configured' is
/// split across the [EmptyState] title and subtitle.
class AuthDisabledView extends StatelessWidget {
  /// Creates the placeholder; [onBack] adds a CTA labeled [ctaLabel].
  const AuthDisabledView({
    this.onBack,
    this.ctaLabel = 'Back',
    super.key,
  });

  /// Invoked by the CTA — pass the screen's pop-or-root navigation.
  final VoidCallback? onBack;

  /// CTA label (welcome uses 'Continue — local only', other screens 'Back').
  final String ctaLabel;

  /// Pops when there is something to pop (pushed from settings), otherwise
  /// lands on the settings root (deep link entry point).
  static void backToSettings(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Sign-in is disabled',
      subtitle: 'SUPABASE_URL not configured',
      ctaLabel: onBack == null ? null : ctaLabel,
      onCta: onBack,
    );
  }
}
