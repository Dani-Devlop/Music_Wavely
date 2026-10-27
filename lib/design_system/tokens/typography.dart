import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Type ramp for Wavely.
///
/// Sora is used for headings, Inter for body/caption text. Call sites may pass
/// a color; when omitted the style inherits from the ambient theme.
abstract final class WavelyTypography {
  static const String fontHeading = 'Sora';
  static const String fontBody = 'Inter';

  static TextStyle display32({Color? color}) =>
      _style(size: 32, weight: FontWeight.w700, family: fontHeading, color: color);

  static TextStyle display24({Color? color}) =>
      _style(size: 24, weight: FontWeight.w700, family: fontHeading, color: color);

  static TextStyle title20({Color? color}) =>
      _style(size: 20, weight: FontWeight.w700, family: fontHeading, color: color);

  static TextStyle title18({Color? color}) =>
      _style(size: 18, weight: FontWeight.w600, family: fontHeading, color: color);

  static TextStyle body14({Color? color}) =>
      _style(size: 14, weight: FontWeight.w400, family: fontBody, color: color);

  static TextStyle body14Medium({Color? color}) =>
      _style(size: 14, weight: FontWeight.w500, family: fontBody, color: color);

  static TextStyle caption12({Color? color}) =>
      _style(size: 12, weight: FontWeight.w400, family: fontBody, color: color);

  static TextStyle micro10({Color? color}) =>
      _style(size: 10, weight: FontWeight.w500, family: fontBody, color: color);

  /// Body style with tabular figures for timers / time sliders.
  static TextStyle timerTabular({Color? color}) =>
      body14(color: color).copyWith(
        fontFeatures: <FontFeature>[const FontFeature.tabularFigures()],
      );

  static TextStyle _style({
    required double size,
    required FontWeight weight,
    required String family,
    Color? color,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        fontFamily: family,
        color: color,
      );
}
