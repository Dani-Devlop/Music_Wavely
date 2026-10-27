import 'package:flutter/material.dart';
import 'package:wavely/core/constants/app_constants.dart';

const int _slowAnimationMs = 500;

/// Motion tokens: durations and the standard easing curve.
abstract final class WavelyDurations {
  static Duration get fast =>
      const Duration(milliseconds: AppConstants.fastAnimationMs);

  static Duration get normal =>
      const Duration(milliseconds: AppConstants.animationMs);

  static Duration get slow => const Duration(milliseconds: _slowAnimationMs);

  static Curve get standard => Curves.easeOutCubic;
}
