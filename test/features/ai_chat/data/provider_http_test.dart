/// Authored, awaiting local run (Stage 3 audit — coverage gap).
///
/// [postJsonWithRetry] contract after the Stage 3 hardening (SEC-5): retry
/// schedule for retryable statuses, fail-fast for client errors, the last
/// response returned as-is when retries exhaust on a 5xx, and the per-
/// attempt timeout added in the audit.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/ai_chat/data/provider_http.dart';

http.Response _json(int code) => http.Response('{"ok":true}', code);

Err<http.Response> _err(Result<http.Response> result) =>
    result as Err<http.Response>;

Future<Result<http.Response>> run({
  required Future<http.Response> Function(http.Request request) handler,
  List<Duration>? delays,
  int maxRetries = 3,
  Duration requestTimeout = const Duration(seconds: 5),
}) =>
    postJsonWithRetry(
      client: MockClient(handler),
      uri: Uri.parse('https://provider.example/v1/chat'),
      headers: const <String, String>{'content-type': 'application/json'},
      body: const <String, Object?>{'ping': true},
      delay: delays == null
          ? null
          : (Duration d) async {
              delays.add(d);
            },
      maxRetries: maxRetries,
      requestTimeout: requestTimeout,
    );

void main() {
  test('200 on the first attempt does not back off', () async {
    final delays = <Duration>[];
    var attempts = 0;
    final result = await run(
      delays: delays,
      maxRetries: 2,
      handler: (_) async {
        attempts++;
        return _json(200);
      },
    );
    expect((result as Success<http.Response>).value.statusCode, 200);
    expect(attempts, 1);
    expect(delays, isEmpty);
  });

  test('retryable 500 then 200 succeeds with one backoff step', () async {
    final delays = <Duration>[];
    final codes = <int>[500, 200];
    var attempt = 0;
    final result = await run(
      delays: delays,
      handler: (_) async => _json(codes[attempt++]),
    );
    expect((result as Success<http.Response>).value.statusCode, 200);
    expect(delays, <Duration>[kProviderBackoff.first]);
  });

  test('429 is retryable', () async {
    final delays = <Duration>[];
    final codes = <int>[429, 429, 200];
    var attempt = 0;
    final result = await run(
      delays: delays,
      handler: (_) async => _json(codes[attempt++]),
    );
    expect((result as Success<http.Response>).value.statusCode, 200);
    expect(delays.length, 2);
  });

  test('exhausted 5xx retries return the last response as-is', () async {
    // Documented contract: non-exception statuses come back even on the
    // final attempt so the caller can fail fast on the body parse.
    final result = await run(
      maxRetries: 2,
      handler: (_) async => _json(500),
    );
    expect((result as Success<http.Response>).value.statusCode, 500);
  });

  test('ClientException retries then succeeds', () async {
    var attempts = 0;
    final result = await run(
      maxRetries: 2,
      handler: (_) async {
        attempts++;
        if (attempts == 1) {
          throw http.ClientException('reset');
        }
        return _json(200);
      },
    );
    expect((result as Success<http.Response>).value.statusCode, 200);
    expect(attempts, 2);
  });

  test('persistent ClientException fails with a friendly message', () async {
    final result = await run(
      maxRetries: 1,
      handler: (_) => throw http.ClientException('offline'),
    );
    final failure = _err(result).failure;
    expect(failure, isA<NetworkFailure>());
    expect((failure as NetworkFailure).message,
        contains('Could not reach the AI provider'));
  });

  test('a stalled provider is cut off by the per-attempt timeout', () async {
    final delays = <Duration>[];
    final result = await run(
      delays: delays,
      maxRetries: 1,
      requestTimeout: const Duration(milliseconds: 40),
      handler: (_) => Completer<http.Response>().future,
    );
    final failure = _err(result).failure;
    expect(failure, isA<NetworkFailure>());
    expect(
      (failure as NetworkFailure).message,
      contains('did not respond in time'),
    );
    // One backoff between attempt 1 and the (also timing-out) attempt 2.
    expect(delays.length, 1);
  });
}
