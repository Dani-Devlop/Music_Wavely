// authored, awaiting local run.
//
// Tests for the Telegram feature's platform-neutral surface:
// - TelegramBridgeState defaults + stub behaviour (io arm).
// - TelegramThemeColors mapping from themeParams (accent/hint/bg/text,
//   legacy fallbacks, unparsable values).
// - resolveTelegramTheme override semantics.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/telegram/telegram_bridge.dart';
import 'package:wavely/features/telegram/telegram_bridge_provider.dart';
import 'package:wavely/features/telegram/telegram_theme_adapter.dart';

void main() {
  group('TelegramBridgeState', () {
    test('default state is not-in-Telegram', () {
      const TelegramBridgeState state = TelegramBridgeState(
        isInTelegram: false,
        initData: '',
      );
      expect(state.isInTelegram, isFalse);
      expect(state.themeParams, isEmpty);
      expect(state.user, isNull);
    });

    test('io stub snapshot is always not-in-Telegram', () {
      final TelegramBridge bridge = createTelegramBridge();
      final TelegramBridgeState snapshot = bridge.snapshot();
      // On the VM (and any io platform) the stub wins.
      expect(snapshot.isInTelegram, isFalse);
      expect(snapshot.initData, isEmpty);
      // Lifecycle calls are safe no-ops.
      expect(() => bridge..ready()..expand()..close(), returnsNormally);
    });
  });

  group('TelegramThemeColors.fromParams', () {
    test('maps documented keys', () {
      final TelegramThemeColors colors = TelegramThemeColors.fromParams(
        <String, String>{
          'bg_color': '#0A0E14',
          'text_color': '#F5F6FA',
          'button_color': '#7C5CFF',
          'hint_color': '#8A93A6',
        },
      );
      expect(colors.background, const Color(0xFF0A0E14));
      expect(colors.text, const Color(0xFFF5F6FA));
      expect(colors.accent, const Color(0xFF7C5CFF));
      expect(colors.hint, const Color(0xFF8A93A6));
    });

    test('parses 6-digit hex without # and falls back on garbage', () {
      final TelegramThemeColors colors = TelegramThemeColors.fromParams(
        <String, String>{
          'bg_color': '123456',
          'text_color': 'not-a-color',
          'button_color': '',
        },
      );
      expect(colors.background, const Color(0xFF123456));
      expect(colors.text, const Color(0xFFF5F6FA), reason: 'garbage → default');
      expect(colors.accent, const Color(0xFF7C5CFF), reason: 'empty → default');
    });

    test('hint falls back to secondary_bg_color then default', () {
      final TelegramThemeColors viaSecondary =
          TelegramThemeColors.fromParams(<String, String>{
        'secondary_bg_color': '#111111',
      });
      expect(viaSecondary.hint, const Color(0xFF111111));
      final TelegramThemeColors viaDefault =
          TelegramThemeColors.fromParams(<String, String>{});
      expect(viaDefault.hint, const Color(0xFF8A93A6));
    });
  });

  group('resolveTelegramTheme', () {
    test('returns null when manual override is on', () {
      const TelegramBridgeState state = TelegramBridgeState(
        isInTelegram: true,
        initData: 'x',
        themeParams: <String, String>{'bg_color': '#111111'},
      );
      expect(
        resolveTelegramTheme(state, manualOverride: true),
        isNull,
      );
    });

    test('returns null when not inside Telegram', () {
      const TelegramBridgeState state = TelegramBridgeState(
        isInTelegram: false,
        initData: '',
        themeParams: <String, String>{'bg_color': '#111111'},
      );
      expect(
        resolveTelegramTheme(state, manualOverride: false),
        isNull,
      );
    });

    test('returns null when themeParams are empty', () {
      const TelegramBridgeState state = TelegramBridgeState(
        isInTelegram: true,
        initData: 'x',
      );
      expect(
        resolveTelegramTheme(state, manualOverride: false),
        isNull,
      );
    });

    test('maps the palette when inside Telegram without override', () {
      const TelegramBridgeState state = TelegramBridgeState(
        isInTelegram: true,
        initData: 'x',
        themeParams: <String, String>{'button_color': '#00FF00'},
      );
      final TelegramThemeColors? resolved =
          resolveTelegramTheme(state, manualOverride: false);
      expect(resolved, isNotNull);
      expect(resolved!.accent, const Color(0xFF00FF00));
    });
  });

  test('kTelegramMode is a compile-time const (false without defines)', () {
    expect(kTelegramMode, isFalse);
  });
}
