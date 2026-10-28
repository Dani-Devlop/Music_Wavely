// authored, awaiting local run.
//
// Tests for lib/features/telegram/telegram_auth_service.dart over a mock
// http client: success path applies the server session, bad signature
// (400), expired (401), network failure and malformed bodies all throw
// TelegramAuthException with the documented codes. The client NEVER
// validates initData itself and NEVER derives identity from it.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:wavely/features/telegram/telegram_auth_service.dart';

class _ScriptedClient extends http_testing.MockClient {
  _ScriptedClient(
    Future<http.Response> Function(http.Request request) fn,
  ) : super((request) => fn(request));

  int calls = 0;
  Map<String, String>? lastHeaders;
  String? lastBody;

  static _ScriptedClient respond(
    int status,
    Map<String, Object?> body,
  ) {
    late final _ScriptedClient client;
    client = _ScriptedClient((http.Request request) async {
      client.calls++;
      client.lastHeaders = request.headers;
      client.lastBody = request.body;
      return http.Response(jsonEncode(body), status);
    });
    return client;
  }

  static _ScriptedClient nonJson(int status) {
    late final _ScriptedClient client;
    client = _ScriptedClient((http.Request request) async {
      client.calls++;
      client.lastHeaders = request.headers;
      client.lastBody = request.body;
      return http.Response('<html>', status);
    });
    return client;
  }

  static _ScriptedClient throwing() =>
      _ScriptedClient((_) async => throw StateError('offline'));
}

TelegramAuthService _service({
  required http.Client client,
  List<Map<String, String>>? applied,
}) =>
    TelegramAuthService(
      client: client,
      endpoint: Uri.https('supabase.example', '/functions/v1/telegram-webapp-auth'),
      anonKey: 'anon-key',
      applySession: (String access, String refresh) async {
        applied?.add(<String, String>{
          'access': access,
          'refresh': refresh,
        });
      },
    );

const String kInitData =
    'query_id=AAH&user=%7B%22id%22%3A279058397%7D&auth_date=1696000000'
    '&hash=deadbeef';

void main() {
  test('success path POSTs initData with apikey and applies the session',
      () async {
    final applied = <Map<String, String>>[];
    final client = _ScriptedClient.respond(200, <String, Object?>{
      'session': <String, Object?>{
        'access_token': 'jwt-access',
        'refresh_token': 'jwt-refresh',
        'expires_in': 3600,
      },
      'user': <String, Object?>{'id': 'uuid-1'},
    });
    await _service(client: client, applied: applied)
        .signIn(initData: kInitData);

    expect(client.calls, 1);
    expect(client.lastHeaders!['apikey'], 'anon-key');
    expect(client.lastHeaders!['content-type'], contains('application/json'));
    final Map<String, Object?> sent =
        jsonDecode(client.lastBody!) as Map<String, Object?>;
    expect(sent['initData'], kInitData,
        reason: 'the RAW initData goes to the server — no client parsing');
    expect(applied, hasLength(1));
    expect(applied.single['access'], 'jwt-access');
    expect(applied.single['refresh'], 'jwt-refresh');
  });

  test('bad signature (400 invalid_signature) throws with the server code',
      () async {
    final applied = <Map<String, String>>[];
    final client = _ScriptedClient.respond(400, <String, Object?>{
      'error': 'invalid_signature',
      'message': 'initData failed HMAC validation.',
    });
    await expectLater(
      _service(client: client, applied: applied).signIn(initData: kInitData),
      throwsA(
        isA<TelegramAuthException>()
            .having((e) => e.code, 'code', 'invalid_signature'),
      ),
    );
    expect(applied, isEmpty);
  });

  test('expired data (401) surfaces the expiry code', () async {
    final client = _ScriptedClient.respond(401, <String, Object?>{
      'error': 'expired',
      'message': 'initData is older than one hour.',
    });
    await expectLater(
      _service(client: client).signIn(initData: kInitData),
      throwsA(
        isA<TelegramAuthException>().having((e) => e.code, 'code', 'expired'),
      ),
    );
  });

  test('network failure maps to the network code', () async {
    final client = _ScriptedClient.throwing();
    await expectLater(
      _service(client: client).signIn(initData: kInitData),
      throwsA(
        isA<TelegramAuthException>().having((e) => e.code, 'code', 'network'),
      ),
    );
  });

  test('non-JSON body maps to malformed_response', () async {
    final client = _ScriptedClient.nonJson(502);
    await expectLater(
      _service(client: client).signIn(initData: kInitData),
      throwsA(isA<TelegramAuthException>()
          .having((e) => e.code, 'code', 'malformed_response')),
    );
  });

  test('200 without a session object maps to malformed_response', () async {
    final client = _ScriptedClient.respond(200, <String, Object?>{
      'unexpected': true,
    });
    await expectLater(
      _service(client: client).signIn(initData: kInitData),
      throwsA(isA<TelegramAuthException>()
          .having((e) => e.code, 'code', 'malformed_response')),
    );
  });

  test('session with empty tokens is rejected', () async {
    final applied = <Map<String, String>>[];
    final client = _ScriptedClient.respond(200, <String, Object?>{
      'session': <String, Object?>{'access_token': '', 'refresh_token': ''},
    });
    await expectLater(
      _service(client: client, applied: applied).signIn(initData: kInitData),
      throwsA(isA<TelegramAuthException>()
          .having((e) => e.code, 'code', 'malformed_response')),
    );
    expect(applied, isEmpty);
  });

  test('empty initData is rejected locally without any request', () async {
    final client = _ScriptedClient.respond(200, <String, Object?>{});
    await expectLater(
      _service(client: client).signIn(initData: ''),
      throwsA(isA<TelegramAuthException>()
          .having((e) => e.code, 'code', 'rejected')),
    );
    expect(client.calls, 0, reason: 'nothing is sent when not in Telegram');
  });
}
