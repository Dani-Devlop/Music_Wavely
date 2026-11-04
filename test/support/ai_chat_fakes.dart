/// Stage 6 E2E — shared AI-chat fakes, extracted from the private copies
/// in the ai_chat screen test so the E2E scenario and the screenshot
/// harness can drive the same scripted flows.
library;

import 'dart:async';

import 'package:wavely/core/errors/result.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Scripted [AiProvider] replaying queued replies in order.
class ScriptedAiProvider implements AiProvider {
  ScriptedAiProvider(this._script);

  final List<AiReply> _script;
  Completer<AiReply>? _gate;
  int calls = 0;

  /// Holds the NEXT complete() call open until [release] is invoked, so the
  /// in-flight UI is deterministic instead of racing microtasks.
  void gateNext() {
    _gate = Completer<AiReply>();
  }

  void release(AiReply reply) {
    _gate?.complete(reply);
    _gate = null;
  }

  @override
  String get id => 'scripted';

  @override
  Future<Result<AiReply>> complete(AiConversation conversation) async {
    calls++;
    if (calls <= _script.length) {
      final AiReply reply = _script[calls - 1];
      if (_gate != null) {
        return _gate!.future.then(Result<AiReply>.success);
      }
      return Result<AiReply>.success(reply);
    }
    return const Result<AiReply>.success(AiReply(text: 'out of script'));
  }
}

/// Records [TrackLauncher.playTracks] calls; nothing else happens.
class RecordingTrackLauncher implements TrackLauncher {
  final List<List<Track>> played = <List<Track>>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    played.add(List<Track>.of(tracks));
  }
}
