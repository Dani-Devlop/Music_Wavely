import 'package:flutter/material.dart';

/// Corner radius tokens.
abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get bSm => BorderRadius.circular(sm);

  static BorderRadius get bMd => BorderRadius.circular(md);

  static BorderRadius get bLg => BorderRadius.circular(lg);

  static BorderRadius get bXl => BorderRadius.circular(xl);

  static BorderRadius get bPill => BorderRadius.circular(pill);
}
