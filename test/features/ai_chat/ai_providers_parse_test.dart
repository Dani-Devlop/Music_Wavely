/// Authored, awaiting local run (Task 2-f).
///
/// Wire-format + parsing tests for [GeminiProvider] and [OpenAiProvider]
/// using hand-rolled [MockClient] transports: fixture payloads for text +
/// function-call replies parse into [AiReply]s, outgoing requests match the
/// documented REST contracts (endpoints, auth, tool schema conversion),
/// 429/5xx go through the shared 500ms/1s/2s backoff with an injectable
/// delay while 4xx fail fast, and [AiProviderFactory] prefers Gemini and
/// degrades to OpenAI → disabled.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/gemini_provider.dart';
import 'package:wavely/features/ai_chat/data/openai_provider.dart';
import 'package:wavely/features/ai_chat/data/provider_http.dart';

/// Records every request and answers from [responses] in order (the last
/// entry repeats). Throws [errors] entries (when given) instead of
/// responding.
class _ScriptedTransport {
  _ScriptedTransport({
    required this.responses,
    this.errors = const <http.ClientException>[],
  });

  final List<http.Response> responses;
  final List<http.ClientException> errors;
  final List<http.Request> requests = <http.Request>[];
  final List<Duration> delays = <Duration>[];
  int _attempt = 0;

  Future<http.Response> handler(http.Request request) async {
    requests.add(request);
    final errorIndex = _attempt - responses.length;
    if (errors.isNotEmpty && errorIndex >= 0) {
      // Repeat the last error for any attempt beyond the scripted count.
      throw errors[errorIndex.clamp(0, errors.length - 1)];
    }
    final index =
        _attempt < responses.length ? _attempt : responses.length - 1;
    _attempt++;
    return responses[index];
  }

  Future<void> recordDelay(Duration d) async {
    delays.add(d);
  }
}

AiConversation _conversationWithToolResult() {
  final call = const AiToolCall(
    id: 'call_1',
    name: 'search_library',
    argumentsJson: '{"query":"neon"}',
  );
  return AiConversation(
    systemPrompt: 'SYSTEM PROMPT',
    messages: <AiMessage>[
      const AiMessage(role: AiMessageRole.user, content: 'hi'),
      AiMessage(
        role: AiMessageRole.assistant,
        content: '',
        toolCallJson: AiMessage.encodeToolCall(call),
      ),
      AiMessage(
        role: AiMessageRole.tool,
        content: '{"matches":[]}',
        toolCallJson: AiMessage.encodeToolCall(call),
      ),
    ],
  );
}

String _geminiToolCallFixture() => jsonEncode(<String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': 'Let me look '},
              <String, Object?>{'text': 'that up.'},
              <String, Object?>{
                'functionCall': <String, Object?>{
                  'name': 'build_queue',
                  'args': <String, Object?>{
                    'track_ids': <Object?>[1, 2],
                    'reason': 'mix',
                  },
                },
              },
            ],
          },
        },
      ],
    });

String _openAiToolCallFixture() => jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{
            'content': 'On it.',
            'tool_calls': <Object?>[
              <String, Object?>{
                'id': 'call_9',
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'search_library',
                  'arguments': '{"query":"neon"}',
                },
              },
            ],
          },
        },
      ],
    });

void main() {
  group('GeminiProvider parsing', () {
    test('parses text parts + functionCall into an AiReply', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(_geminiToolCallFixture(), 200),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
      );
      final result = await provider.complete(
        AiConversation(
          systemPrompt: 'SYSTEM PROMPT',
          messages: const <AiMessage>[
            AiMessage(role: AiMessageRole.user, content: 'hi'),
          ],
        ),
      );
      final reply = result.fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (r) => r,
      );
      expect(reply.text, 'Let me look that up.');
      expect(reply.toolCalls, hasLength(1));
      final call = reply.toolCalls!.single;
      expect(call.id, 'gemini-call-1');
      expect(call.name, 'build_queue');
      expect(
        jsonDecode(call.argumentsJson),
        <String, Object?>{'track_ids': <Object?>[1, 2], 'reason': 'mix'},
      );
    });

    test('text-only replies carry no tool calls', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(
            jsonEncode(<String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'content': <String, Object?>{
                    'parts': <Object?>[
                      <String, Object?>{'text': 'hello there'},
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
      );
      final reply = (await provider.complete(
        AiConversation(systemPrompt: 'S'),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (r) => r,
      );
      expect(reply.text, 'hello there');
      expect(reply.toolCalls, isNull);
    });

    test('outgoing request matches the documented wire contract', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(_geminiToolCallFixture(), 200),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
      );
      await provider.complete(_conversationWithToolResult());
      final request = transport.requests.single;
      expect(
        request.url.toString(),
        contains(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-2.0-flash:generateContent?key=gm-key',
        ),
      );
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final systemInstruction = body['systemInstruction'] as Map;
      final systemPart = (systemInstruction['parts'] as List).single as Map;
      expect(systemPart['text'], 'SYSTEM PROMPT');
      final contents = body['contents'] as List<Object?>;
      expect(contents, hasLength(3));
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model');
      // Tool results are replayed as user text parts (documented
      // simplification).
      expect((contents[2] as Map)['role'], 'user');
      expect(
        (((contents[2] as Map)['parts'] as List).single as Map)['text'],
        'Tool result: {"matches":[]}',
      );
      final declarations =
          ((body['tools'] as List).single as Map)['functionDeclarations']
              as List<Object?>;
      expect(
        [for (final d in declarations) (d as Map)['name']],
        <String>[
          'search_library',
          'build_queue',
          'create_playlist',
          'get_listening_stats',
        ],
      );
    });

    test('malformed payloads surface typed parsing failures', () async {
      Future<void> expectParseError(
        String body,
        String message,
      ) async {
        final transport = _ScriptedTransport(
          responses: <http.Response>[http.Response(body, 200)],
        );
        final provider = GeminiProvider(
          apiKey: 'gm-key',
          httpClient: MockClient(transport.handler),
        );
        final result = await provider.complete(
          AiConversation(systemPrompt: 'S'),
        );
        result.fold(
          onErr: (f) {
            expect(f, isA<ParsingFailure>());
            expect(f.message, message);
          },
          onSuccess: (_) => fail('expected a parsing failure'),
        );
      }

      await expectParseError(
        'not-json',
        'Gemini returned invalid JSON.',
      );
      await expectParseError(
        jsonEncode(<String, Object?>{}),
        'Gemini returned no candidates.',
      );
      await expectParseError(
        jsonEncode(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': 'nope',
              },
            },
          ],
        }),
        'Gemini content has no parts.',
      );
    });
  });

  group('OpenAiProvider parsing', () {
    test('parses tool_calls into an AiReply', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(_openAiToolCallFixture(), 200),
        ],
      );
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        httpClient: MockClient(transport.handler),
      );
      final reply = (await provider.complete(
        AiConversation(systemPrompt: 'SYSTEM PROMPT'),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (r) => r,
      );
      expect(reply.text, 'On it.');
      expect(reply.toolCalls, hasLength(1));
      final call = reply.toolCalls!.single;
      expect(call.id, 'call_9');
      expect(call.name, 'search_library');
      expect(call.argumentsJson, '{"query":"neon"}');
    });

    test('null message content parses to empty text', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(
            jsonEncode(<String, Object?>{
              'choices': <Object?>[
                <String, Object?>{
                  'message': <String, Object?>{
                    'content': null,
                    'tool_calls': <Object?>[
                      <String, Object?>{
                        'id': 'call_1',
                        'type': 'function',
                        'function': <String, Object?>{
                          'name': 'search_library',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        ],
      );
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        httpClient: MockClient(transport.handler),
      );
      final reply = (await provider.complete(
        AiConversation(systemPrompt: 'S'),
      ))
          .fold(
        onErr: (f) => throw StateError('expected success: ${f.message}'),
        onSuccess: (r) => r,
      );
      expect(reply.text, '');
      expect(reply.toolCalls, hasLength(1));
    });

    test('outgoing request matches the documented wire contract', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(_openAiToolCallFixture(), 200),
        ],
      );
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        httpClient: MockClient(transport.handler),
      );
      await provider.complete(_conversationWithToolResult());
      final request = transport.requests.single;
      expect(
        request.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(request.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'gpt-4o-mini');
      final messages = body['messages'] as List<Object?>;
      expect(messages, hasLength(3));
      expect((messages[0] as Map)['role'], 'system');
      expect((messages[0] as Map)['content'], 'SYSTEM PROMPT');
      // Assistant turns replay the tool_calls; executor results go back as
      // role:'tool' with the originating id.
      final assistant = messages[1] as Map<String, Object?>;
      expect(assistant['role'], 'assistant');
      final replayed = (assistant['tool_calls'] as List).single as Map;
      expect(replayed['id'], 'call_1');
      expect((replayed['function'] as Map)['name'], 'search_library');
      final tool = messages[2] as Map<String, Object?>;
      expect(tool['role'], 'tool');
      expect(tool['tool_call_id'], 'call_1');
      expect(tool['content'], '{"matches":[]}');
      // Same schemas, converted to the OpenAI shape with lowercased types.
      final tools = body['tools'] as List<Object?>;
      expect(tools, hasLength(4));
      final first = tools[0] as Map<String, Object?>;
      expect(first['type'], 'function');
      final parameters =
          (first['function'] as Map<String, Object?>)['parameters']
              as Map<String, Object?>;
      expect(parameters['type'], 'object');
      final trackIds =
          (parameters['properties'] as Map<String, Object?>)['track_ids']
              as Map<String, Object?>;
      expect(trackIds['type'], 'array');
      expect((trackIds['items'] as Map<String, Object?>)['type'],
          'integer');
    });

    test('responses without choices surface parsing failures', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response(jsonEncode(<String, Object?>{}), 200),
        ],
      );
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        httpClient: MockClient(transport.handler),
      );
      final result = await provider.complete(
        AiConversation(systemPrompt: 'S'),
      );
      result.fold(
        onErr: (f) => expect(f.message, 'OpenAI returned no choices.'),
        onSuccess: (_) => fail('expected a parsing failure'),
      );
    });
  });

  group('shared retry policy (postJsonWithRetry via the providers)', () {
    test('429 → backoff once → success records the 500ms wait', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response('rate limited', 429),
          http.Response(_geminiToolCallFixture(), 200),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
        delay: transport.recordDelay,
      );
      final result =
          await provider.complete(AiConversation(systemPrompt: 'S'));
      expect(result.isSuccess, isTrue);
      expect(transport.requests, hasLength(2));
      expect(transport.delays, kProviderBackoff.take(1));
    });

    test('persistent 429 → 4 requests, full backoff, friendly error',
        () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response('rate limited', 429),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
        delay: transport.recordDelay,
      );
      final result =
          await provider.complete(AiConversation(systemPrompt: 'S'));
      expect(transport.requests, hasLength(4)); // 1 + 3 retries
      expect(transport.delays, kProviderBackoff);
      result.fold(
        onErr: (f) => expect(
          f.message,
          'Gemini is rate limiting requests — try again shortly.',
        ),
        onSuccess: (_) => fail('expected the rate-limit failure'),
      );
    });

    test('5xx retries and then succeeds', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response('boom', 503),
          http.Response('boom', 503),
          http.Response(_openAiToolCallFixture(), 200),
        ],
      );
      final provider = OpenAiProvider(
        apiKey: 'sk-test',
        httpClient: MockClient(transport.handler),
        delay: transport.recordDelay,
      );
      final result =
          await provider.complete(AiConversation(systemPrompt: 'S'));
      expect(result.isSuccess, isTrue);
      expect(transport.requests, hasLength(3));
      expect(transport.delays, kProviderBackoff.take(2));
    });

    test('4xx fails fast with exactly one request', () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[
          http.Response('bad key', 400),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
        delay: transport.recordDelay,
      );
      final result =
          await provider.complete(AiConversation(systemPrompt: 'S'));
      expect(transport.requests, hasLength(1));
      expect(transport.delays, isEmpty);
      result.fold(
        onErr: (f) => expect(f.message, contains('invalid API key?')),
        onSuccess: (_) => fail('400 must not be retried'),
      );
    });

    test('transport exceptions exhaust the retries with a network error',
        () async {
      final transport = _ScriptedTransport(
        responses: <http.Response>[],
        errors: <http.ClientException>[
          http.ClientException('socket closed'),
        ],
      );
      final provider = GeminiProvider(
        apiKey: 'gm-key',
        httpClient: MockClient(transport.handler),
        delay: transport.recordDelay,
      );
      final result =
          await provider.complete(AiConversation(systemPrompt: 'S'));
      expect(transport.requests, hasLength(4));
      expect(transport.delays, kProviderBackoff);
      result.fold(
        onErr: (f) => expect(
          f.message,
          'Could not reach the AI provider — check your connection.',
        ),
        onSuccess: (_) => fail('expected the network failure'),
      );
    });
  });

  group('AiProviderFactory fallback', () {
    Never _noRequests(http.Request request) =>
        throw StateError('transport must never be called');

    test('prefers Gemini when both keys are present', () {
      final provider = AiProviderFactory.create(
        geminiKey: 'gm',
        openAiKey: 'sk',
        httpClient: MockClient(_noRequests),
      );
      expect(provider!.id, 'gemini');
    });

    test('falls back to OpenAI when only that key is present', () {
      final provider = AiProviderFactory.create(
        openAiKey: 'sk',
        httpClient: MockClient(_noRequests),
      );
      expect(provider!.id, 'openai');
    });

    test('returns null (feature disabled) without usable keys', () {
      expect(AiProviderFactory.create(), isNull);
      expect(AiProviderFactory.create(geminiKey: '   '), isNull);
      // Whitespace-only keys are ignored — OpenAI still gets picked up.
      expect(
        AiProviderFactory.create(
          geminiKey: ' ',
          openAiKey: 'sk',
          httpClient: MockClient(_noRequests),
        )!
            .id,
        'openai',
      );
    });
  });
}
