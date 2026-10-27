import 'package:wavely/core/constants/app_constants.dart';

/// Backdrop blur sigma budgets (mirrors AppConstants so call sites read
/// naturally next to the other design tokens).
abstract final class WavelyBlur {
  static double get surface => AppConstants.blurSigmaSurface;

  static double get elevated => AppConstants.blurSigmaElevated;
}
