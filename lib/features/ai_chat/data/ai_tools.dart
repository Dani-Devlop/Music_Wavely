import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/local/db/daos/tracks_dao.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Tool schemas exposed to the models, in the Gemini `functionDeclarations`
/// format (types uppercase per the v1beta REST contract).
///
/// `openai_provider.dart` mirrors these exact schemas in the OpenAI
/// `tools:[{type:'function', function:{...}}]` shape; keep both in sync when
/// a tool is added or changed here.
const List<Map<String, Object>> aiToolDeclarations = <Map<String, Object>>[
  <String, Object>{
    'name': 'search_library',
    'description':
        'Full-text search over the user\'s local music library. Use before '
        'build_queue/create_playlist to discover real track ids.',
    'parameters': <String, Object>{
      'type': 'OBJECT',
      'properties': <String, Object>{
        'query': <String, Object>{
          'type': 'STRING',
          'description': 'Free-text query: title, artist or album words.',
        },
      },
      'required': <String>['query'],
    },
  },
  <String, Object>{
    'name': 'build_queue',
    'description':
        'Replaces the playback queue with the given tracks and starts '
        'playing. Only ids returned by search_library are valid.',
    'parameters': <String, Object>{
      'type': 'OBJECT',
      'properties': <String, Object>{
        'track_ids': <String, Object>{
          'type': 'ARRAY',
          'items': <String, Object>{'type': 'INTEGER'},
          'description': 'Library track ids from search_library results.',
        },
        'reason': <String, Object>{
          'type': 'STRING',
          'description': 'Why this queue was built (shown to the user).',
        },
      },
      'required': <String>['track_ids'],
    },
  },
  <String, Object>{
    'name': 'create_playlist',
    'description': 'Creates a named playlist containing the given tracks.',
    'parameters': <String, Object>{
      'type': 'OBJECT',
      'properties': <String, Object>{
        'name': <String, Object>{'type': 'STRING'},
        'track_ids': <String, Object>{
          'type': 'ARRAY',
          'items': <String, Object>{'type': 'INTEGER'},
        },
      },
      'required': <String>['name', 'track_ids'],
    },
  },
  <String, Object>{
    'name': 'get_listening_stats',
    'description': 'Aggregated listening statistics for a time period.',
    'parameters': <String, Object>{
      'type': 'OBJECT',
      'properties': <String, Object>{
        'period': <String, Object>{
          'type': 'STRING',
          'description': 'One of: today, week, month, year, lifetime.',
        },
      },
      'required': <String>['period'],
    },
  },
];

/// Names accepted by [AiToolExecutor.execute].
const List<String> aiToolNames = <String>[
  'search_library',
  'build_queue',
  'create_playlist',
  'get_listening_stats',
];

/// What one tool execution produced.
@immutable
class AiToolOutcome {
  const AiToolOutcome({
    required this.toolName,
    required this.resultJson,
    required this.summary,
    this.queuedTracks = const <Track>[],
    this.queueReason,
  });

  final String toolName;

  /// Short human-readable line for the chat transcript.
  final String summary;

  /// JSON string fed back to the model as the tool message content.
  final String resultJson;

  /// Tracks validated against the database AND actually handed to the
  /// launcher (only ever populated by `build_queue`).
  final List<Track> queuedTracks;

  final String? queueReason;

  /// True when this outcome mutated the playback queue.
  bool get builtQueue => queuedTracks.isNotEmpty;
}

/// Executes AI tool calls against LOCAL data with strict validation.
///
/// Wire-up notes (orchestrator):
/// - [createPlaylist] is a callback because Stage 1.1 has playlists tables
///   but no playlists DAO yet; wire it when the playlists feature lands.
///   `null` → the tool honestly reports unavailability.
/// - [listeningStatsFallback] lets the orchestrator bridge the analytics
///   feature without importing it here; `null` → 'stats unavailable'.
///
/// SECURITY: [execute] is the ONLY path from model output to playback. Track
/// ids are re-resolved via [TracksDao.byIds]; any id that does not exist in
/// the library fails the whole call ("fabricated ids rejected") and nothing
/// is queued. Model text claiming ids is never trusted by [AiService].
class AiToolExecutor {
  AiToolExecutor({
    required this.tracksDao,
    required this.launcher,
    this.createPlaylist,
    this.listeningStatsFallback,
  });

  final TracksDao tracksDao;
  final TrackLauncher launcher;

  /// Orchestrator-provided bridge to the (future) playlists feature.
  final Future<void> Function(String name, List<int> trackIds)? createPlaylist;

  /// Orchestrator-provided bridge to the analytics repository; takes a
  /// period (`today|week|month|year|lifetime`) and returns a JSON stats
  /// string (or null when unavailable).
  final Future<String?> Function(String period)? listeningStatsFallback;

  /// Runs [call] and returns either an [AiToolOutcome] or a typed failure.
  Future<Result<AiToolOutcome>> execute(AiToolCall call) async {
    switch (call.name) {
      case 'search_library':
        return _searchLibrary(call);
      case 'build_queue':
        return _buildQueue(call);
      case 'create_playlist':
        return _createPlaylist(call);
      case 'get_listening_stats':
        return _listeningStats(call);
      default:
        return Result.err(
          Failure.unknown(message: 'Unknown tool: ${call.name}'),
        );
    }
  }

  Future<Result<AiToolOutcome>> _searchLibrary(AiToolCall call) async {
    final args = _decodeArgs(call.argumentsJson);
    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return const Result.err(
        Failure.unknown(message: 'search_library requires a query'),
      );
    }
    final matches = await tracksDao.searchFts(query);
    return Result.success(
      AiToolOutcome(
        toolName: call.name,
        summary: 'Found ${matches.length} matches for "$query".',
        resultJson: jsonEncode(<String, Object>{
          'matches': <Object>[
            for (final track in matches.take(20))
              <String, Object>{
                'id': track.id ?? -1,
                'title': track.title,
                'artist': track.artistOrUnknown,
              },
          ],
        }),
      ),
    );
  }

  Future<Result<AiToolOutcome>> _buildQueue(AiToolCall call) async {
    final args = _decodeArgs(call.argumentsJson);
    final requested = _parseIntList(args['track_ids']);
    if (requested.isEmpty) {
      return const Result.err(
        Failure.unknown(message: 'build_queue requires non-empty track_ids'),
      );
    }
    final found = await tracksDao.byIds(requested);
    final foundIds = <int>{
      for (final track in found)
        if (track.id != null) track.id!,
    };
    final missing = requested.where((id) => !foundIds.contains(id)).toList();
    if (missing.isNotEmpty) {
      // Fabricated ids: reject the WHOLE call, never partially queue.
      return Result.err(
        Failure.unknown(message: 'Unknown track ids: $missing'),
      );
    }
    await launcher.playTracks(found);
    final reason = args['reason'] as String?;
    return Result.success(
      AiToolOutcome(
        toolName: call.name,
        summary: 'Queued ${found.length} tracks'
            '${reason == null ? '.' : ' — $reason.'}',
        resultJson: jsonEncode(<String, Object?>{
          'queued': found.length,
          'reason': reason,
        }),
        queuedTracks: found,
        queueReason: reason,
      ),
    );
  }

  Future<Result<AiToolOutcome>> _createPlaylist(AiToolCall call) async {
    final hook = createPlaylist;
    if (hook == null) {
      return const Result.err(
        Failure.unknown(
          message: 'playlist creation lands with the playlists feature',
        ),
      );
    }
    final args = _decodeArgs(call.argumentsJson);
    final name = (args['name'] as String?)?.trim() ?? '';
    final ids = _parseIntList(args['track_ids']);
    if (name.isEmpty || ids.isEmpty) {
      return const Result.err(
        Failure.unknown(message: 'create_playlist requires name + track_ids'),
      );
    }
    final found = await tracksDao.byIds(ids);
    final foundIds = <int>{
      for (final track in found)
        if (track.id != null) track.id!,
    };
    final missing = ids.where((id) => !foundIds.contains(id)).toList();
    if (missing.isNotEmpty) {
      return Result.err(
        Failure.unknown(message: 'Unknown track ids: $missing'),
      );
    }
    await hook(name, ids);
    return Result.success(
      AiToolOutcome(
        toolName: call.name,
        summary: 'Created playlist "$name" with ${ids.length} tracks.',
        resultJson: jsonEncode(<String, Object?>{
          'created': name,
          'trackCount': ids.length,
        }),
      ),
    );
  }

  Future<Result<AiToolOutcome>> _listeningStats(AiToolCall call) async {
    final hook = listeningStatsFallback;
    final args = _decodeArgs(call.argumentsJson);
    final period = (args['period'] as String?) ?? 'lifetime';
    if (hook == null) {
      return const Result.success(
        AiToolOutcome(
          toolName: 'get_listening_stats',
          summary: 'Listening stats are not wired up yet.',
          resultJson: '{"stats":"unavailable"}',
        ),
      );
    }
    final stats = await hook(period);
    return Result.success(
      AiToolOutcome(
        toolName: call.name,
        summary: 'Listening stats for $period ready.',
        resultJson: stats ?? '{"stats":"unavailable","period":"$period"}',
      ),
    );
  }

  Map<String, Object?> _decodeArgs(String argumentsJson) {
    if (argumentsJson.trim().isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      return const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  List<int> _parseIntList(Object? raw) {
    if (raw is! List) {
      return const <int>[];
    }
    return <int>[
      for (final value in raw)
        if (value is num) value.toInt(),
    ];
  }
}
