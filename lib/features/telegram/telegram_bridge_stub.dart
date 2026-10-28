import 'package:wavely/features/telegram/telegram_bridge.dart';

/// IO/test stub: there is no Telegram bridge outside a browser.
class TelegramBridgeStub implements TelegramBridge {
  const TelegramBridgeStub();

  static const TelegramBridgeState _state = TelegramBridgeState(
    isInTelegram: false,
    initData: '',
  );

  @override
  TelegramBridgeState snapshot() => _state;

  @override
  void ready() {}

  @override
  void expand() {}

  @override
  void close() {}
}

/// Factory selected by the conditional export in `telegram_bridge.dart`.
TelegramBridge createPlatformTelegramBridge() => const TelegramBridgeStub();
