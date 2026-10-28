import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';

/// Backoff schedule between retry attempts (500ms → 1s → 2s).
const List<Duration> kProviderBackoff = <Duration>[
  Duration(milliseconds: 500),
  Duration(seconds: 1),
  Duration(seconds: 2),
];

/// Stage 3 audit (SEC-5): per-attempt request timeout.
const Duration kProviderHttpTimeout = Duration(seconds: 30);

Future<void> _defaultDelay(Duration d) => Future<void>.delayed(d);

/// POSTs a JSON body with the shared retry policy used by every
/// [AiProvider] implementation:
/// - up to 3 RETRIES (4 requests total) on HTTP 429 and 5xx, and on
///   transport-level `http.ClientException`s, with [kProviderBackoff] waits
///   in between;
/// - any other status (400/401/403/404, ...) is returned as-is so the caller
///   can fail fast — invalid API keys must never be retried.
///
/// [delay] is injectable so tests run the full schedule instantly.
Future<Result<http.Response>> postJsonWithRetry({
  required http.Client client,
  required Uri uri,
  required Map<String, String> headers,
  required Map<String, Object?> body,
  Future<void> Function(Duration delay)? delay,
  int maxRetries = 3,
  Duration requestTimeout = kProviderHttpTimeout,
}) async {
  final sleep = delay ?? _defaultDelay;
  final payload = jsonEncode(body);
  for (var attempt = 0; attempt <= maxRetries; attempt++) {
    if (attempt > 0) {
      await sleep(kProviderBackoff[attempt - 1]);
    }
    http.Response response;
    try {
      // Stage 3 audit (SEC-5): bound each attempt so a stalled provider
      // cannot hang the retry loop indefinitely.
      response = await client
          .post(
            uri,
            headers: headers,
            body: payload,
          )
          .timeout(requestTimeout);
    } on TimeoutException catch (e) {
      if (attempt == maxRetries) {
        return Result.err(
          Failure.network(
            message: 'The AI provider did not respond in time.',
            cause: e,
          ),
        );
      }
      continue;
    } on http.ClientException catch (e) {
      if (attempt == maxRetries) {
        return Result.err(
          Failure.network(
            message: 'Could not reach the AI provider — check your '
                'connection.',
            cause: e,
          ),
        );
      }
      continue;
    }
    final retryable = response.statusCode == 429 || response.statusCode >= 500;
    if (retryable && attempt < maxRetries) {
      continue;
    }
    return Result.success(response);
  }
  // Unreachable: the loop always returns or continues into a final attempt.
  return const Result.err(
    Failure.network(message: 'AI provider did not respond.'),
  );
}
