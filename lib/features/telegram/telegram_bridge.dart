export 'telegram_bridge_stub.dart'
    if (dart.library.js_interop) 'telegram_bridge_web.dart';

/// Platform-neutral snapshot of the Telegram Mini App environment.
class TelegramBridgeState {
  /// Creates a snapshot.
  const TelegramBridgeState({
    required this.isInTelegram,
    required this.initData,
    this.themeParams = const <String, String>{},
    this.user,
  });

  /// True when the app runs inside a Telegram Mini App with real
  /// `initData` (an embedded browser without initData is NOT Telegram).
  final bool isInTelegram;

  /// Raw initData string; ONLY ever sent to the validation edge function —
  /// never trusted on the client.
  final String initData;

  /// Parsed themeParams (`bg_color`, `text_color`, `button_color`,
  /// `hint_color`, ...). Empty off-Telegram.
  final Map<String, String> themeParams;

  /// UNVALIDATED user object from `initDataUnsafe` (display purposes only:
  /// first name / username avatar text). Identity comes exclusively from
  /// the server-validated session — see [TelegramAuthService].
  final Map<String, Object?>? user;
}

/// Platform-neutral seam over `window.Telegram.WebApp`.
///
/// - Web arm: real bindings over `telegram_web_app.dart`.
/// - IO arm ([telegram_bridge_stub.dart]): everything empty/false — the
///   Mini App only exists in a browser.
/// - Tests: inject a fake implementing this interface.
abstract interface class TelegramBridge {
  /// Reads the current Mini App snapshot. Never throws (off-Telegram or
  /// inaccessible bridge → not-in-Telegram state).
  TelegramBridgeState snapshot();

  /// Tells Telegram the app is ready (no-op off-Telegram).
  void ready();

  /// Expands the Mini App (no-op off-Telegram).
  void expand();

  /// Closes the Mini App (no-op off-Telegram).
  void close();
}

/// Builds the platform bridge (web bindings vs. no-op stub).
TelegramBridge createTelegramBridge() => createPlatformTelegramBridge();
