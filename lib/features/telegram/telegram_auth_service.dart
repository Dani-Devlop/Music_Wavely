import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the Telegram sign-in round fails. The [code] mirrors the
/// edge function's `error` field so the UI can show honest messages.
class TelegramAuthException implements Exception {
  const TelegramAuthException(this.code, this.message);

  /// Machine-readable code: `invalid_signature` | `expired` | `rejected` |
  /// `network` | `malformed_response`.
  final String code;

  /// Human-readable message.
  final String message;

  @override
  String toString() => 'TelegramAuthException($code): $message';
}

/// Applied session callback seam — production wires
/// `supabase.auth.setSession(accessToken, refreshToken)`; tests record the
/// call. The session values come EXCLUSIVELY from the edge-function
/// response (the client never trusts `initDataUnsafe.user.id`).
typedef TelegramSessionApplier = Future<void> Function(
  String accessToken,
  String refreshToken,
);

/// Telegram Mini App sign-in (Stage 2.2).
///
/// Flow:
/// 1. The bridge supplies the raw `initData` query string.
/// 2. This service POSTs it to the `telegram-webapp-auth` edge function.
/// 3. The function validates the HMAC (bot token), checks `auth_date`
///    freshness and find-or-creates the Supabase user — see
///    `supabase/functions/telegram-webapp-auth/index.ts`.
/// 4. The returned session JWT pair is applied through [TelegramSessionApplier].
///
/// The client performs NO validation of its own: HMAC validation requires
/// the bot token, which must never ship to the client.
class TelegramAuthService {
  /// Creates the service.
  ///
  /// [endpoint] is the deployed edge-function URL; [anonKey] is the public
  /// Supabase anon key (sent as the `apikey` header).
  TelegramAuthService({
    required http.Client client,
    required Uri endpoint,
    required String anonKey,
    required TelegramSessionApplier applySession,
  })  : _client = client,
        _endpoint = endpoint,
        _anonKey = anonKey,
        _applySession = applySession;

  final http.Client _client;
  final Uri _endpoint;
  final String _anonKey;
  final TelegramSessionApplier _applySession;

  /// Runs the sign-in round for [initData]. Throws [TelegramAuthException]
  /// on any failure path.
  Future<void> signIn({required String initData}) async {
    if (initData.isEmpty) {
      throw const TelegramAuthException(
        'rejected',
        'Not inside Telegram (initData is empty).',
      );
    }
    final http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: <String, String>{
          'apikey': _anonKey,
          'content-type': 'application/json',
        },
        body: jsonEncode(<String, String>{'initData': initData}),
      );
    } on Object catch (error) {
      throw TelegramAuthException('network', 'Sign-in request failed: $error');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw TelegramAuthException(
        'malformed_response',
        'Edge function returned a non-JSON body (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode != 200 || decoded is! Map<String, Object?>) {
      throw TelegramAuthException(
        _errorCode(decoded, response.statusCode),
        _errorMessage(decoded, response.statusCode),
      );
    }
    final Object? session = decoded['session'];
    if (session is! Map<String, Object?>) {
      throw const TelegramAuthException(
        'malformed_response',
        'Edge function response has no session object.',
      );
    }
    final String accessToken = (session['access_token'] ?? '').toString();
    final String refreshToken = (session['refresh_token'] ?? '').toString();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const TelegramAuthException(
        'malformed_response',
        'Edge function session has empty tokens.',
      );
    }
    await _applySession(accessToken, refreshToken);
  }

  static String _errorCode(Object? body, int statusCode) {
    if (body is Map<String, Object?> && body['error'] is String) {
      return body['error'] as String;
    }
    if (statusCode == 400) {
      return 'invalid_signature';
    }
    if (statusCode == 401) {
      return 'expired';
    }
    return 'rejected';
  }

  static String _errorMessage(Object? body, int statusCode) {
    if (body is Map<String, Object?> && body['message'] is String) {
      return body['message'] as String;
    }
    return 'Telegram sign-in failed (HTTP $statusCode).';
  }
}
