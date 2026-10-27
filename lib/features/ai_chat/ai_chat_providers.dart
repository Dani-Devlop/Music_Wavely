import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/core/config/env.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_provider.dart';
import 'package:wavely/features/ai_chat/data/ai_service.dart';
import 'package:wavely/features/ai_chat/data/ai_tools.dart';
import 'package:wavely/features/ai_chat/data/library_snapshot.dart';
import 'package:wavely/features/library/data/track_launcher.dart';

/// Best available chat model from configured env keys (Gemini first, then
/// OpenAI); `null` when no key is present → the feature renders its setup
/// state instead of the chat.
final aiModelProvider = Provider<AiProvider?>(
  (ref) => AiProviderFactory.create(
    geminiKey: WavelyEnv.geminiApiKey,
    openAiKey: WavelyEnv.openAiApiKey,
  ),
);

/// Tool executor over the local database + playback launcher.
///
/// Orchestrator notes: pass `createPlaylist:` once the playlists feature
/// exists and `listeningStatsFallback:` to bridge the analytics repository
/// (this file must not import analytics directly). Both are `null` for now,
/// so those tools answer honestly that they are unavailable.
final aiToolExecutorProvider = Provider<AiToolExecutor>((ref) {
  final db = ref.watch(databaseProvider);
  return AiToolExecutor(
    tracksDao: db.tracksDao,
    launcher: ref.watch(trackLauncherProvider),
  );
});

/// Full chat service, or `null` when the feature is disabled. Tests override
/// this provider directly to inject fakes.
final aiServiceProvider = Provider<AiService?>((ref) {
  final model = ref.watch(aiModelProvider);
  if (model == null) {
    return null;
  }
  final db = ref.watch(databaseProvider);
  return AiService(
    provider: model,
    executor: ref.watch(aiToolExecutorProvider),
    snapshotLoader: () => LibrarySnapshot.build(tracksDao: db.tracksDao),
  );
});
