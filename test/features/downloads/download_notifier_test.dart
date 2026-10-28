// authored, awaiting local run.
//
// Tests for lib/features/downloads/data/download_notifier.dart: the no-op
// implementation completes silently; the flutter_local_notifications-backed
// implementation degrades to a no-op when the platform channel is absent
// (exactly the widget-test environment — a MissingPluginException inside
// initialize() must never propagate).

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/downloads/data/download_notifier.dart';

void main() {
  group('NoopDownloadNotifier', () {
    test('all three notifications complete without doing anything',
        () async {
      final NoopDownloadNotifier n = NoopDownloadNotifier();
      await n.notifyStarted('Aurora');
      await n.notifyCompleted('Aurora');
      await n.notifyFailed('Aurora', 'boom');
    });
  });

  group('LocalDownloadNotifier (no platform channel)', () {
    test('initialize failure degrades to silent no-op, never throws',
        () async {
      final LocalDownloadNotifier n = LocalDownloadNotifier();
      // In the test environment the plugin channel is missing; the
      // guarded initialisation must swallow the error.
      await n.notifyStarted('Aurora');
      await n.notifyCompleted('Aurora');
      await n.notifyFailed('Aurora', 'boom');
    });

    test('repeated calls stay silent (init attempted once)', () async {
      final LocalDownloadNotifier n = LocalDownloadNotifier();
      for (var i = 0; i < 3; i++) {
        await n.notifyStarted('track $i');
      }
    });
  });
}
