import 'package:wavely/core/constants/app_constants.dart';

/// Backdrop blur sigma budgets (mirrors AppConstants so call sites read
/// naturally next to the other design tokens).
///
/// Phase 10: [scale] is the settings-driven blur-strength multiplier
/// (0..2, default 1). The theme provider keeps it in sync with the
/// canonical [AppSettings.blurScale]; `reduceTransparency` zeroes it.
abstract final class WavelyBlur {
  /// Runtime blur multiplier (design tokens = 1). Mutable on purpose: the
  /// theme provider writes it whenever the settings change so the whole
  /// design system reads one value without plumbing Riverpod through leaf
  /// widgets.
  static double scale = 1;

  static double get surface => AppConstants.blurSigmaSurface * scale;

  static double get elevated => AppConstants.blurSigmaElevated * scale;
}
