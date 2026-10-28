/// Authored, awaiting local run (Stage 3 audit — coverage gap).
///
/// [DownloadEvent] model contract: defaults, field carry-through, and the
/// [DownloadStatus] lifecycle values the download manager emits.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/tables/downloads.dart';
import 'package:wavely/features/downloads/data/download_events.dart';

void main() {
  group('DownloadEvent', () {
    test('progress defaults are applied', () {
      const event = DownloadEvent(
        rowId: 7,
        status: DownloadStatus.queued,
      );
      expect(event.rowId, 7);
      expect(event.status, DownloadStatus.queued);
      expect(event.progress, 0);
      expect(event.error, isNull);
    });

    test('carries progress and error payloads', () {
      const event = DownloadEvent(
        rowId: 42,
        status: DownloadStatus.failed,
        progress: 88,
        error: 'size mismatch',
      );
      expect(event.progress, 88);
      expect(event.error, 'size mismatch');
    });

    test('is const-constructible for the emit paths', () {
      // The manager emits const events; compile-time constness is the
      // contract here.
      const a = DownloadEvent(rowId: 1, status: DownloadStatus.completed);
      const b = DownloadEvent(rowId: 1, status: DownloadStatus.completed);
      expect(a.status, b.status);
    });
  });

  group('DownloadStatus lifecycle', () {
    test('covers the full manager lifecycle', () {
      expect(
        DownloadStatus.values,
        containsAll(<DownloadStatus>[
          DownloadStatus.queued,
          DownloadStatus.downloading,
          DownloadStatus.completed,
          DownloadStatus.failed,
          DownloadStatus.canceled,
        ]),
      );
    });

    test('storage names are the DB string contract', () {
      expect(DownloadStatus.queued.name, 'queued');
      expect(DownloadStatus.downloading.name, 'downloading');
      expect(DownloadStatus.completed.name, 'completed');
      expect(DownloadStatus.failed.name, 'failed');
      expect(DownloadStatus.canceled.name, 'canceled');
    });
  });
}
