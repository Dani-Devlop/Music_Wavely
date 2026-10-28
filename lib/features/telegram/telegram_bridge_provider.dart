import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_riverpod/legacy.dart';
import 'package:wavely/features/telegram/telegram_bridge.dart';

/// Compile-time Telegram Mini App build flag:
/// `flutter build web --dart-define=TELEGRAM_MODE=true`.
/// See bootstrap (host lifecycle) and docs/TELEGRAM_MINIAPP.md.
const bool kTelegramMode = bool.fromEnvironment('TELEGRAM_MODE');

/// The platform Telegram bridge (real bindings on web, no-op elsewhere).
///
/// Tests override with a fake implementing [TelegramBridge].
final telegramBridgeProvider = Provider<TelegramBridge>((ref) {
  return createTelegramBridge();
});

/// Reactive snapshot of the Mini App environment. The WebApp object does
/// not emit change events for theme/user, so this is a plain Provider —
/// rebuilds happen on theme-override changes, not bridge pushes.
final telegramStateProvider = Provider<TelegramBridgeState>((ref) {
  return ref.watch(telegramBridgeProvider).snapshot();
});
