import 'package:flutter/material.dart';

/// Corner radius tokens.
///
/// Phase 10: [scale] is the settings-driven radius multiplier (0.5..2,
/// default 1). The theme provider keeps it in sync with the canonical
/// [AppSettings.radiusScale]; every radius getter multiplies through it so
/// the whole design system re-rounds without per-widget plumbing.
abstract final class AppRadii {
  /// Runtime radius multiplier (design tokens = 1). Mutable on purpose —
  /// see WavelyBlur.scale for the rationale.
  static double scale = 1;

  static double get sm => 8 * scale;
  static double get md => 12 * scale;
  static double get lg => 16 * scale;
  static double get xl => 24 * scale;
  static const double pill = 999;

  static BorderRadius get bSm => BorderRadius.circular(sm);

  static BorderRadius get bMd => BorderRadius.circular(md);

  static BorderRadius get bLg => BorderRadius.circular(lg);

  static BorderRadius get bXl => BorderRadius.circular(xl);

  static BorderRadius get bPill => BorderRadius.circular(pill);
}
