import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:wavely/features/telegram/telegram_bridge.dart';
import 'package:wavely/features/telegram/telegram_web_app.dart';

/// Real web bindings over `window.Telegram.WebApp`.
class TelegramBridgeWeb implements TelegramBridge {
  const TelegramBridgeWeb();

  @override
  TelegramBridgeState snapshot() {
    try {
      final TelegramWebApp app = telegramWebApp;
      final String initData = app.initData;
      return TelegramBridgeState(
        isInTelegram: initData.isNotEmpty,
        initData: initData,
        themeParams: _stringifyThemeParams(app.themeParams),
        user: _stringifyObject(app.initDataUnsafe),
      );
    } on Object {
      // Script not loaded / not inside Telegram → honest not-in-Telegram.
      return const TelegramBridgeState(isInTelegram: false, initData: '');
    }
  }

  @override
  void ready() {
    try {
      telegramWebApp.ready();
    } on Object {
      // No-op off-Telegram.
    }
  }

  @override
  void expand() {
    try {
      telegramWebApp.expand();
    } on Object {
      // No-op off-Telegram.
    }
  }

  @override
  void close() {
    try {
      telegramWebApp.close();
    } on Object {
      // No-op off-Telegram.
    }
  }

  /// Converts the themeParams JSObject into a Dart string map via
  /// JSON.stringify (no per-key property walking needed).
  static Map<String, String> _stringifyThemeParams(JSObject params) {
    final Map<String, Object?> decoded = _stringifyObject(params);
    return <String, String>{
      for (final MapEntry<String, Object?> entry in decoded.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }

  static Map<String, Object?> _stringifyObject(JSObject object) {
    try {
      final JSObject json = globalContext.getProperty('JSON'.toJS) as JSObject;
      final JSString encoded =
          json.callMethod<JSString>('stringify'.toJS, object);
      final Object? decoded = jsonDecode(encoded.toDart);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on Object {
      // Fall through to the empty map.
    }
    return const <String, Object?>{};
  }
}

/// Factory selected by the conditional export in `telegram_bridge.dart`.
TelegramBridge createPlatformTelegramBridge() => const TelegramBridgeWeb();
