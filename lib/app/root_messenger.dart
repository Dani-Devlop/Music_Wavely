import 'package:flutter/material.dart';

/// Root [ScaffoldMessenger] key — the single SnackBar surface for the app.
///
/// Wired into `MaterialApp.router(scaffoldMessengerKey: ...)` so non-UI
/// layers (the parental preload hook runs inside a Riverpod provider, far
/// from any BuildContext) can surface user-visible feedback. Stage 3 final
/// polish (BUG-9): skipped/muted explicit tracks need a UI toast.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>(debugLabel: 'rootMessenger');

/// Best-effort snackbar. No-ops before the MaterialApp exists (widget
/// tests, headless runs) and never throws — a toast must never break
/// playback.
void showRootSnackBar(String message) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) {
    return;
  }
  try {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } on Object catch (_) {
    // No messenger, no toast, no crash.
  }
}
