import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Matches absolute-path-like substrings such as `/home/user/secret/file.mp3`.
final RegExp _pathLikePattern = RegExp(r'(/[\w.\-]+){3,}');

const String _pathPlaceholder = '<path>';

/// Replaces path-like substrings with `<path>`.
///
/// Used before persisting or reporting log messages in release builds so that
/// no PII (user names, folder layouts) leaks into crash reports.
String sanitizeForRelease(String message) =>
    message.replaceAllMapped(_pathLikePattern, (_) => _pathPlaceholder);

/// Message pipeline shared by all [AppLogger] methods: debug builds keep full
/// detail, release builds get [sanitizeForRelease].
@visibleForTesting
String prepareLogMessage(String message) =>
    kDebugMode ? message : sanitizeForRelease(message);

/// Thin wrapper around `package:logger`.
///
/// Usage: `AppLogger.I.d('scan finished')`.
class AppLogger {
  const AppLogger._();

  static const AppLogger _instance = AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

  /// Shared logger instance.
  static AppLogger get I => _instance;

  /// Debug-level log; dropped entirely in release builds.
  void d(String message, {Object? error, StackTrace? stackTrace}) {
    if (kReleaseMode) {
      return;
    }
    _logger.d(prepareLogMessage(message), error: error, stackTrace: stackTrace);
  }

  /// Info-level log; dropped entirely in release builds.
  void i(String message, {Object? error, StackTrace? stackTrace}) {
    if (kReleaseMode) {
      return;
    }
    _logger.i(prepareLogMessage(message), error: error, stackTrace: stackTrace);
  }

  /// Warning-level log; sanitized in release builds.
  void w(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.w(prepareLogMessage(message), error: error, stackTrace: stackTrace);
  }

  /// Error-level log; sanitized in release builds.
  void e(String message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(prepareLogMessage(message), error: error, stackTrace: stackTrace);
  }
}
