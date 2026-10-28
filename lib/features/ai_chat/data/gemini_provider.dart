import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/provider_http.dart';

/// Google Gemini chat provider (REST, no SDK).
///
/// Wire contract (documented against the public Generative Language REST
/// docs): POST
/// `https://generativelanguage.googleapis.com/v1beta/models/`
/// `gemini-2.0-flash:generateContent?key=<key>`
/// with `contents[] {role: 'user'|'model', parts:[{text}]}`,
/// `systemInstruction`, and
/// `tools: [{functionDeclarations: [...]}]` ([aiToolDeclarations]).
///
/// Notes / simplifications:
/// - Tool RESULTS from our executor are appended as `user` turns with a
///   plain-text part (`Tool <name> result: <json>`); the neutral
///   [AiConversation] shape does not carry Gemini `functionResponse` parts.
/// - Invalid API keys surface as 400/403 and fail immediately (no retry);
///   429/5xx go through the shared backoff in [postJsonWithRetry].
class GeminiProvider implements AiProvider {
  GeminiProvider({
    required this.apiKey,
    http.Client? httpClient,
    Future<void> Function(Duration delay)? delay,
  })  : _client = httpClient ?? http.Client(),
        _delay = delay;

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  final String apiKey;
  final http.Client _client;
  final Future<void> Function(Duration delay)? _delay;

  @override
  String get id => 'gemini';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    // Stage 3 audit (SEC-10): the API key moved from the URL query string
    // (leaks into proxy logs / exception messages) to a request header.
    final uri = Uri.parse(_endpoint);
    final response = await postJsonWithRetry(
      client: _client,
      uri: uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
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
        'systemInstruction': <String, Object?>{
          'parts': <Object>[
            <String, Object?>{'text': conversation.systemPrompt},
          ],
        },
        'contents': <Object>[
          for (final message in conversation.messages)
            <String, Object?>{
              'role': switch (message.role) {
                AiMessageRole.user => 'user',
                AiMessageRole.assistant => 'model',
                AiMessageRole.tool => 'user',
              },
              'parts': <Object>[
                if (message.role == AiMessageRole.tool)
                  <String, Object?>{
                    'text': 'Tool result: ${message.content}',
                  }
                else
                  <String, Object?>{'text': message.content},
              ],
            },
        ],
        'tools': <Object>[
          <String, Object?>{'functionDeclarations': aiToolDeclarations},
        ],
      };

  Result<AiReply> _parse(http.Response response) {
    if (response.statusCode != 200) {
      return Result.err(_failureFor(response));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      return Result.err(
        Failure.parsing(message: 'Gemini returned invalid JSON.', cause: e),
      );
    }
    if (decoded is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'Gemini response was not an object.'),
      );
    }
    // Shape verified against the Gemini function-calling docs
    // (ai.google.dev/gemini-api/docs/function-calling): candidates[].content
    // .parts[], each part either {text} or {functionCall: {name, args}}.
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return const Result.err(
        Failure.parsing(message: 'Gemini returned no candidates.'),
      );
    }
    final first = candidates.first;
    if (first is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'Gemini candidate was malformed.'),
      );
    }
    final content = first['content'];
    if (content is! Map<String, Object?>) {
      return const Result.err(
        Failure.parsing(message: 'Gemini candidate has no content.'),
      );
    }
    final parts = content['parts'];
    if (parts is! List) {
      return const Result.err(
        Failure.parsing(message: 'Gemini content has no parts.'),
      );
    }
    final text = StringBuffer();
    final toolCalls = <AiToolCall>[];
    var callIndex = 0;
    for (final part in parts) {
      if (part is! Map<String, Object?>) {
        continue;
      }
      final partText = part['text'];
      if (partText is String) {
        text.write(partText);
      }
      final functionCall = part['functionCall'];
      if (functionCall is Map<String, Object?>) {
        callIndex++;
        final args = functionCall['args'];
        toolCalls.add(
          AiToolCall(
            id: 'gemini-call-$callIndex',
            name: functionCall['name'] as String? ?? '',
            argumentsJson: jsonEncode(args ?? <String, Object?>{}),
          ),
        );
      }
    }
    return Result.success(
      AiReply(
        text: text.toString(),
        toolCalls: toolCalls.isEmpty ? null : toolCalls,
      ),
    );
  }

  Failure _failureFor(http.Response response) {
    final body = response.body;
    if (response.statusCode == 400 || response.statusCode == 403) {
      return Failure.network(
        message: 'Gemini rejected the request (invalid API key?). '
            'HTTP ${response.statusCode}.',
        cause: body,
      );
    }
    if (response.statusCode == 429) {
      return const Failure.network(
        message: 'Gemini is rate limiting requests — try again shortly.',
      );
    }
    return Failure.network(
      message: 'Gemini request failed (HTTP ${response.statusCode}).',
      cause: body,
    );
  }
}
