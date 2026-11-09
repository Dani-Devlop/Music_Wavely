/// Musicolet-clone palette + shared sheet chrome for the v1.0.2
/// platform-adaptive UI (Android layout, width < 800).
///
/// The owner spec pins the Android experience to a strict Musicolet look:
/// charcoal surfaces, compact rows and the signature Musicolet green for
/// accents, section headers and primary actions. These tokens are used by
/// the song-options sheet, the queue-manager sheet, the scan / sleep-timer
/// dialogs and the dedicated equalizer screen.
library;

import 'package:flutter/material.dart';

/// Musicolet-clone color tokens.
abstract final class MusicoletColors {
  /// The signature Musicolet green (context-menu icons, section headers,
  /// SCAN NOW / REMOVE ALL buttons, EQ sliders).
  static const Color green = Color(0xFF4CAF50);

  /// Darker green used for pressed / container states.
  static const Color greenDark = Color(0xFF2E7D32);

  /// Charcoal sheet background (Musicolet's bottom sheets / dialogs).
  static const Color sheet = Color(0xFF1E1F22);

  /// Slightly lighter charcoal for cards inside sheets.
  static const Color sheetCard = Color(0xFF27292D);

  /// Hairline divider inside sheets.
  static const Color divider = Color(0xFF3A3D42);

  /// Primary text on charcoal.
  static const Color text = Color(0xFFF2F3F5);

  /// Secondary text on charcoal.
  static const Color textDim = Color(0xFF9AA0A6);
}

/// Builds a Musicolet-style showModalBottomSheet route: dark charcoal
/// surface, top-rounded, no default drag handle (Musicolet has none).
Future<T?> showMusicoletSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: MusicoletColors.sheet,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: builder,
  );
}
