/// dart:js_interop bindings over the Telegram WebApp JS bridge
/// (https://core.telegram.org/bots/webapps#initializing-mini-apps).
///
/// WEB-ONLY: this library is imported exclusively from
/// `telegram_bridge_web.dart`, which is selected by the conditional import
/// in `telegram_bridge.dart` — the same pattern as the playback engines.
///
/// The script `https://telegram.org/js/telegram-web-app.js` must be present
/// in `web/index.html` (it is, see the Stage 2.2 index template).
library;

import 'dart:js_interop';

/// `window.Telegram.WebApp`
@JS('Telegram.WebApp')
external TelegramWebApp get telegramWebApp;

/// Minimal surface of the Telegram WebApp object Wavely needs.
extension type TelegramWebApp._(JSObject _) implements JSObject {
  /// Tells Telegram the Mini App finished loading.
  external void ready();

  /// Expands the Mini App to full height.
  external void expand();

  /// Closes the Mini App.
  external void close();

  /// Theme parameters as a plain JS object of color strings.
  external JSObject get themeParams;

  /// Raw `initData` query string (validated SERVER-SIDE only).
  external String get initData;

  /// Parsed `initDataUnsafe` (UNVALIDATED — never trust on the client).
  external JSObject get initDataUnsafe;

  /// MainButton API (exposed for future use; unused today).
  external JSObject get MainButton;

  /// BackButton API (exposed for future use; unused today).
  external JSObject get BackButton;

  /// HapticFeedback API (exposed for future use; unused today).
  external JSObject get HapticFeedback;
}
