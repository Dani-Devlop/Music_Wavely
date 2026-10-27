import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/provider_http.dart';

/// OpenAI chat-completions fallback provider (REST, no SDK).
///
/// Wire contract: POST `https://api.openai.com/v1/chat/completions` with
/// `Authorization: Bearer <key>`, `model: 'gpt-4o-mini'`, `messages[]` and
/// `tools[]` carrying the SAME schemas as [aiToolDeclarations] (converted to
/// the OpenAI `{"type":"function","function":{...}}` shape with lowercase
/// JSON-schema types).
///
/// Notes / simplifications:
/// - Assistant turns that requested tools are replayed with a `tool_calls`
  /// array; executor results are appended as `role:'tool'` messages with
///   the originating call id.
/// - Invalid API keys surface as 401/403 and fail immediately (no retry);
///   429/5xx go through the shared backoff in [postJsonWithRetry].
class OpenAiProvider implements AiProvider {
  OpenAiProvider({
    required this.apiKey,
    http.Client? httpClient,
    Future<void> Function(Duration delay)? delay,
  })  : _client = httpClient ?? http.Client(),
        _delay = delay;

  static const String _endpoint =
      'https://api.openai.com/v1/chat/completions';
  static const String _model = 'gpt-4o-mini';

  final String apiKey;
  final http.Client _client;
  final Future<void> Function(Duration delay)? _delay;

  @override
  String get id => 'openai';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    final response = await postJsonWithRetry(
      client: _client,
      uri: Uri.parse(_endpoint),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: _buildBody(conversation),
      delay: _delay,
    );
    return response.fold(
      onErr: Result<AiReply>.err,
      onSuccess: (res) => _parse(res),
    );
  }

  Map<String, Object?> _buildBody(AiConversation conversation) =>
      <String, Object?>{
        'model': _model,
        'messages': <Object>[
          <String, Object?>{
            'role': 'system',
            'content': conversation.systemPrompt,
          },
          for (final message in conversation.messages)
            ..._wireMessage(message),
        ],
        'tools': <Object>[
          for (final declaration in aiToolDeclarations)
            <String, Object?>{
              'type': 'function',
              'function': _toOpenAiFunction(declaration),
            },
        ],
      };

  List<Map<String, Object?>> _wireMessage(AiMessage message) {
    if (message.role == AiMessageRole.tool) {
      final callId = _toolCallIdOf(message.toolCallJson);
      return <Map<String, Object?>>[
        <String, Object?>{
          'role': 'tool',
          'tool_call_id': callId,
          'content': message.content,
        },
      ];
    }
    final wire = <String, Object?>{
      'role': message.role == AiMessageRole.assistant ? 'assistant' : 'user',
      'content': message.content,
    };
    final call = AiMessage.decodeToolCall(message.toolCallJson);
    if (message.role == AiMessageRole.assistant && call != null) {
      wire['tool_calls'] = <Object>[
        <String, Object?>{
          'id': call.id,
          'type': 'function',
          'function': <String, Object?>{
            'name': call.name,
            'arguments': call.argumentsJson,
          },
        },
      ];
    }
    return <Map<String, Object?>>[wire];
  }

  static String? _toolCallIdOf(String? toolCallJson) =>
      AiMessage.decodeToolCall(toolCallJson)?.id;

  Map<String, Object?> _toOpenAiFunction(Map<String, Object?> declaration) =>
      <String, Object?>{
        'name': declaration['name'],
        'description': declaration['description'],
        'parameters': _lowercaseTypes(declaration['parameters']),
      };

  Object? _lowercaseTypes(Object? node) {
    if (node is Map<String, Object?>) {
      return <String, Object?>{
        for (final entry in node.entries)
          entry.key:
              entry.key == 'type' && entry.value is String
                  ? (entry.value as String).toLowerCase()
                  : _lowercaseTypes(entry.value),
      };
    }
    if (node is List) {
      return <Object>[for (final item in node) _lowercaseTypes(item)];
    }
    return node;
  }

  Result<AiReply> _parse(http.Response response) {
    if (response.statusCode != 200) {
      return Result.err(_failureFor(response));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      return Result.err(
        Failure.parsing(message: 'OpenAI returned invalid JSON.', cause: e),
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'OpenAI response was not an object.'),
      );
    }
    // Shape verified against the official OpenAI OpenAPI spec
    // (github.com/openai/openai-openapi): choices[].message.tool_calls[],
    // each entry {id, type: "function", function: {name, arguments}}.
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return const Result.err(
        Failure.parsing(message: 'OpenAI returned no choices.'),
      );
    }
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'OpenAI choice was malformed.'),
      );
    }
    final message = first['message'];
    if (message is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'OpenAI choice has no message.'),
      );
    }
    final toolCalls = <AiToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls) {
        if (raw is! Map<String, Object?>) {
          continue;
        }
        final function = raw['function'];
        if (function is! Map<String, Object?>) {
          continue;
        }
        toolCalls.add(
          AiToolCall(
            id: raw['id'] as String? ?? '',
            name: function['name'] as String? ?? '',
            argumentsJson: function['arguments'] as String? ?? '{}',
          ),
        );
      }
    }
    return Result.success(
      AiReply(
        text: message['content'] as String? ?? '',
        toolCalls: toolCalls.isEmpty ? null : toolCalls,
      ),
    );
  }

  Failure _failureFor(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return Failure.network(
        message: 'OpenAI rejected the request (invalid API key?). '
            'HTTP ${response.statusCode}.',
        cause: response.body,
      );
    }
    if (response.statusCode == 429) {
      return const Failure.network(
        message: 'OpenAI is rate limiting requests — try again shortly.',
      );
    }
    return Failure.network(
      message: 'OpenAI request failed (HTTP ${response.statusCode}).',
      cause: response.body,
    );
  }
}
