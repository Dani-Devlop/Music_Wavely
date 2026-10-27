/// Authored, awaiting local run (Task 2-a).
///
/// Tests for `lib/core/utils/logger.dart` through its public surface:
/// - `sanitizeForRelease` — the PII path-masking regex (release behavior).
/// - `prepareLogMessage` — the shared pipeline (`@visibleForTesting`); in
///   `flutter test` the app is compiled in debug mode (`kDebugMode` true),
///   so the pipeline passes messages through verbatim. The release branch
///   (`sanitizeForRelease`) is only reachable behind a `--release` compile
///   and is therefore covered via [sanitizeForRelease] directly.
/// - `AppLogger.I` — singleton identity plus a smoke run of every level
///   (`d`/`i` are dropped in release builds, `w`/`e` are always emitted;
///   level filtering itself is compile-time `kReleaseMode` logic and the
///   internal `package:logger` instance is not injectable, so the
///   observable contract here is: no throw, correct routing of the
///   error/stackTrace parameters).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/utils/logger.dart';

void main() {
  group('sanitizeForRelease', () {
    test('replaces absolute-path-like runs with <path>', () {
      expect(sanitizeForRelease('open /home/user/file.mp3'), 'open <path>');
      expect(
        sanitizeForRelease('see /var/log/app/error.log now'),
        'see <path> now',
      );
      expect(
        sanitizeForRelease('/home/user/secret/file.mp3'),
        '<path>',
      );
    });

    test('collapses a path embedded mid-sentence', () {
      expect(
        sanitizeForRelease('scan of /music/flac/album/track.flac failed'),
        'scan of <path> failed',
      );
    });

    test('leaves short relative runs (fewer than 3 segments) alone', () {
      expect(sanitizeForRelease('/music/song.mp3'), '/music/song.mp3');
      expect(sanitizeForRelease('x /a/b y'), 'x /a/b y');
      expect(sanitizeForRelease('plain text, no path'), 'plain text, no path');
    });

    test('handles multiple paths in one message', () {
      expect(
        sanitizeForRelease('copy /a/b/c to /x/y/z'),
        'copy <path> to <path>',
      );
    });
  });

  group('prepareLogMessage', () {
    test('passes the message through verbatim in debug builds', () {
      // flutter_test compiles in debug mode; kDebugMode guards the branch.
      expect(kDebugMode, isTrue);
      expect(
        prepareLogMessage('scan finished /home/user/file.mp3'),
        'scan finished /home/user/file.mp3',
      );
      expect(prepareLogMessage(''), '');
    });
  });

  group('AppLogger', () {
    test('exposes a stable singleton', () {
      expect(identical(AppLogger.I, AppLogger.I), isTrue);
    });

    test('every level accepts a message without throwing', () {
      // In debug builds d/i pass through the shared pipeline; in release
      // they are dropped. Either way the call must be side-effect free for
      // the caller (no exceptions).
      expect(() => AppLogger.I.d('debug message'), returnsNormally);
      expect(() => AppLogger.I.i('info message'), returnsNormally);
      expect(() => AppLogger.I.w('warning message'), returnsNormally);
      expect(() => AppLogger.I.e('error message'), returnsNormally);
    });

    test('every level forwards error and stackTrace without throwing', () {
      final error = StateError('boom');
      final stackTrace = StackTrace.current;
      expect(
        () => AppLogger.I.d('d', error: error, stackTrace: stackTrace),
        returnsNormally,
      );
      expect(
        () => AppLogger.I.i('i', error: error, stackTrace: stackTrace),
        returnsNormally,
      );
      expect(
        () => AppLogger.I.w('w', error: error, stackTrace: stackTrace),
        returnsNormally,
      );
      expect(
        () => AppLogger.I.e('e', error: error, stackTrace: stackTrace),
        returnsNormally,
      );
    });

    test('warn/error accept a non-Exception error objects', () {
      expect(
        () => AppLogger.I.e('non-exception cause', error: 'raw string'),
        returnsNormally,
      );
      expect(
        () => AppLogger.I.w('null error is fine', error: null),
        returnsNormally,
      );
    });
  });
}
