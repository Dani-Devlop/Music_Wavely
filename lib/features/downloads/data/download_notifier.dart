import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// User-facing notifications for download lifecycle changes.
///
/// Behind an interface so widget/service tests never touch the
/// flutter_local_notifications platform channel.
abstract class DownloadNotifier {
  /// Shows (or coalesces) the "download started" notification.
  Future<void> notifyStarted(String title);

  /// Shows the "download completed" notification.
  Future<void> notifyCompleted(String title);

  /// Shows the "download failed" notification with [reason].
  Future<void> notifyFailed(String title, String reason);
}

/// No-op notifier (tests, and platforms without notification support).
class NoopDownloadNotifier implements DownloadNotifier {
  const NoopDownloadNotifier();
  @override
  Future<void> notifyStarted(String title) async {}

  @override
  Future<void> notifyCompleted(String title) async {}

  @override
  Future<void> notifyFailed(String title, String reason) async {}
}

/// flutter_local_notifications-backed implementation.
///
/// Initialisation is lazy and guarded: a plugin failure (channel missing,
/// permission denied, tests) degrades to a no-op — downloads must never
/// crash because a notification could not be shown. Authored, awaiting
/// local run (channel only initialises on real devices).
class LocalDownloadNotifier implements DownloadNotifier {
  /// Creates the notifier; [plugin] injectable for tests.
  LocalDownloadNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const int _startedId = 42001;
  static const int _completedId = 42002;
  static const int _failedId = 42003;

  bool _initAttempted = false;
  bool _available = false;

  Future<void> _ensureInit() async {
    if (_initAttempted) {
      return;
    }
    _initAttempted = true;
    try {
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const InitializationSettings settings = InitializationSettings(
        android: android,
        iOS: ios,
        macOS: ios,
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      );
      _available = await _plugin.initialize(settings: settings) ?? false;
    } on Object {
      _available = false;
    }
  }

  Future<void> _show(int id, String title, String body) async {
    await _ensureInit();
    if (!_available) {
      return;
    }
    try {
      const AndroidNotificationDetails android = AndroidNotificationDetails(
        'downloads',
        'Downloads',
        channelDescription: 'Download started / completed / failed',
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
      );
      const DarwinNotificationDetails darwin = DarwinNotificationDetails(
        presentSound: false,
      );
      const NotificationDetails details = NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.show(id: id, title: title, body: body, notificationDetails: details);
    } on Object {
      // Notification failures never break the download flow.
    }
  }

  @override
  Future<void> notifyStarted(String title) =>
      _show(_startedId, 'Wavely', 'Download started: $title');

  @override
  Future<void> notifyCompleted(String title) =>
      _show(_completedId, 'Wavely', 'Download completed: $title');

  @override
  Future<void> notifyFailed(String title, String reason) =>
      _show(_failedId, 'Wavely', 'Download failed: $title ($reason)');
}
