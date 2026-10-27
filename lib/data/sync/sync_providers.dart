import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wavely/core/config/env.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/sync/sync_backend.dart';
import 'package:wavely/data/sync/sync_service.dart';
import 'package:wavely/data/sync/supabase_sync_backend.dart';
import 'package:wavely/design_system/themes/theme_provider.dart';

/// Remote sync backend binding.
///
/// Returns null unless `WavelyEnv.hasSupabase` — without configured keys the
/// [SyncService] idles in `SyncStatus.disabled` and nothing touches the
/// network. Uses a standalone [SupabaseClient] (no `Supabase.initialize`):
/// the sync feature only needs the data API, not the full SDK session flow.
final syncBackendProvider = Provider<SyncBackend?>((ref) {
  final url = WavelyEnv.supabaseUrl;
  final anonKey = WavelyEnv.supabaseAnonKey;
  if (url == null || anonKey == null) {
    return null;
  }
  return SupabaseSyncBackend(client: SupabaseClient(url, anonKey));
});

/// App-wide sync engine binding (never auto-started — the composition root
/// calls `start()` after bootstrap; see the ORCHESTRATOR WIRING note below).
// ORCHESTRATOR WIRING — kick the engine after bootstrap, e.g. at the end of
// `lib/app/bootstrap.dart` (or from MainShell's initState):
//
//   final container = ...; // the ProviderContainer/app reference
//   unawaited(
//     container.read(syncServiceProvider).start(
//           connectivityChanges: Connectivity()
//               .onConnectivityChanged
//               .map((statuses) => statuses.contains(ConnectivityResult.none)
//                   ? false
//                   : true),
//         ),
//   );
//
// (`connectivity_plus` 7.x emits List<ConnectivityResult>; the map collapses
// it to the `Stream<bool>` the engine accepts. Tests inject a
// StreamController<bool> instead.)
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = SyncService(
    db: db,
    outboxDao: db.syncOutboxDao,
    playsDao: db.playsDao,
    tracksDao: db.tracksDao,
    settingsStore: ref.watch(settingsStoreProvider),
    backend: ref.watch(syncBackendProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
