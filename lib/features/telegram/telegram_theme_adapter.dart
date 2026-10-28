import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/features/telegram/telegram_bridge.dart';
import 'package:wavely/features/telegram/telegram_bridge_provider.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

/// Prefs key: manual theme override (Telegram theme follows the app when
/// this is `false`, which is the default).
const String kTelegramThemeOverrideKey = 'telegram.themeOverride';

/// Mapped Telegram theme palette (Stage 2.2).
class TelegramThemeColors {
  const TelegramThemeColors({
    required this.background,
    required this.text,
    required this.accent,
    required this.hint,
  });

  /// Maps Telegram `themeParams` (`bg_color`, `text_color`, `button_color`,
  /// `hint_color` and legacy `secondary_bg_color`) onto Wavely token roles.
  /// Missing/unparsable values fall back to the supplied defaults.
  factory TelegramThemeColors.fromParams(
    Map<String, String> params, {
    Color background = const Color(0xFF0A0E14),
    Color text = const Color(0xFFF5F6FA),
    Color accent = const Color(0xFF7C5CFF),
    Color hint = const Color(0xFF8A93A6),
  }) {
    Color? parse(String? raw) {
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final String hex = raw.replaceFirst('#', '').trim();
      final String normalized = hex.length == 6 ? 'FF$hex' : hex;
      final int? value = int.tryParse(normalized, radix: 16);
      return value == null ? null : Color(value);
    }

    return TelegramThemeColors(
      background: parse(params['bg_color']) ?? background,
      text: parse(params['text_color']) ?? text,
      accent: parse(params['button_color']) ?? accent,
      hint: parse(params['hint_color']) ??
          parse(params['secondary_bg_color']) ??
          hint,
    );
  }

  final Color background;
  final Color text;
  final Color accent;
  final Color hint;

  @override
  bool operator ==(Object other) =>
      other is TelegramThemeColors &&
      other.background == background &&
      other.text == text &&
      other.accent == accent &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(background, text, accent, hint);
}

/// Resolves the palette to apply: Telegram's themeParams when the bridge
/// reports being inside Telegram AND the user has not chosen the manual
/// override; otherwise `null` (= keep the in-app theme).
TelegramThemeColors? resolveTelegramTheme(
  TelegramBridgeState state, {
  required bool manualOverride,
}) {
  if (manualOverride || !state.isInTelegram || state.themeParams.isEmpty) {
    return null;
  }
  return TelegramThemeColors.fromParams(state.themeParams);
}

/// Convenience over the providers: `null` = keep the in-app theme.
TelegramThemeColors? telegramThemeFromRef(Ref ref) {
  return resolveTelegramTheme(
    ref.watch(telegramStateProvider),
    manualOverride:
        ref.watch(sharedPrefsProvider).getBool(kTelegramThemeOverrideKey) ??
            false,
  );
}
