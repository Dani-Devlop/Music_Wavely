import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/features/ai_chat/data/gemini_provider.dart';
import 'package:wavely/features/ai_chat/data/openai_provider.dart';

/// Role of one turn inside an [AiConversation].
enum AiMessageRole { user, assistant, tool }

/// A single conversation turn exchanged with an [AiProvider].
@immutable
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    this.toolCallJson,
  });

  final AiMessageRole role;

  /// Text content of the turn; for [AiMessageRole.tool] this is the JSON
  /// result the tool produced.
  final String content;

  /// JSON-serialized [AiToolCall] this message relates to (assistant messages
  /// that requested tools, and the tool messages answering them).
  final String? toolCallJson;

  /// Serializes [call] into the [toolCallJson] representation.
  static String encodeToolCall(AiToolCall call) => jsonEncode(<String, String>{
        'id': call.id,
        'name': call.name,
        'argumentsJson': call.argumentsJson,
      });

  /// Deserializes a [toolCallJson] payload back into an [AiToolCall].
  static AiToolCall? decodeToolCall(String? toolCallJson) {
    if (toolCallJson == null || toolCallJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(toolCallJson);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return AiToolCall(
        id: decoded['id'] as String? ?? '',
        name: decoded['name'] as String? ?? '',
        argumentsJson: decoded['argumentsJson'] as String? ?? '{}',
      );
    } on FormatException {
      return null;
    }
  }
}

/// A tool invocation requested by the model.
@immutable
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  /// Provider-side (or synthesized) identifier of the call.
  final String id;

  /// Tool name; must match a key exposed in the tool schemas.
  final String name;

  /// JSON object string with the tool arguments.
  final String argumentsJson;
}

/// The provider's answer for one turn: text plus optional tool calls.
@immutable
class AiReply {
  const AiReply({required this.text, this.toolCalls});

  final String text;
  final List<AiToolCall>? toolCalls;
}

/// Immutable conversation handed to [AiProvider.complete].
@immutable
class AiConversation {
  const AiConversation({
    required this.systemPrompt,
    this.messages = const <AiMessage>[],
  });

  final String systemPrompt;
  final List<AiMessage> messages;

  AiConversation copyWith({List<AiMessage>? messages}) => AiConversation(
        systemPrompt: systemPrompt,
        messages: messages ?? this.messages,
      );
}

/// Transport-agnostic chat-model interface.
///
/// Implementations ([GeminiProvider], [OpenAiProvider]) translate the neutral
/// [AiConversation] shape into their wire format and parse replies back into
/// [AiReply]s. All failures surface as `Result.err` — implementers never
/// throw for expected conditions (HTTP errors, bad payloads, ...).
abstract interface class AiProvider {
  /// Stable provider identifier ('gemini' / 'openai').
  String get id;

  /// Runs one completion turn over [conversation].
  Future<Result<AiReply>> complete(AiConversation conversation);
}

/// Builds the best available [AiProvider] from configured API keys.
///
/// Preference order: Gemini first, then OpenAI. When neither key is present
/// the AI-chat feature is disabled and `null` is returned.
abstract final class AiProviderFactory {
  /// Creates a provider from the given keys.
  ///
  /// [httpClient] and [delay] are injectable for tests (fake transport and
  /// instant backoff); production callers omit them.
  static AiProvider? create({
    String? geminiKey,
    String? openAiKey,
    http.Client? httpClient,
    Future<void> Function(Duration delay)? delay,
  }) {
    if (geminiKey != null && geminiKey.trim().isNotEmpty) {
      return GeminiProvider(
        apiKey: geminiKey,
        httpClient: httpClient,
        delay: delay,
      );
    }
    if (openAiKey != null && openAiKey.trim().isNotEmpty) {
      return OpenAiProvider(
        apiKey: openAiKey,
        httpClient: httpClient,
        delay: delay,
      );
    }
    return null;
  }
}
