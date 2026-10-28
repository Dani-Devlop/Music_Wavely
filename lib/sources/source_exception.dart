/// Thrown when an online source answers a protocol error (non-JSON body,
/// error envelope, missing resource). Shared by every Stage 2.1 provider so
/// the unified search and download manager can handle one failure shape.
class SourceApiException implements Exception {
  /// Creates the exception with a human-readable [message].
  const SourceApiException(this.message);

  /// Failure description.
  final String message;

  @override
  String toString() => 'SourceApiException: $message';
}
