/// Authored, awaiting local run (Task 2-a).
///
/// Harness that pumps the REAL `lib/app/wavely_app.dart` [WavelyApp] with
/// the composition-root overrides from `lib/app/providers.dart`
/// ([buildOverrides]) pointed at hermetic fakes:
///
/// - Drift database → `AppDatabase(NativeDatabase.memory())` (in-memory
///   SQLite, no filesystem) — `AppDatabase` documents exactly this
///   constructor for tests.
/// - SharedPreferences → `SharedPreferences.setMockInitialValues` (plugin
///   mocked by the package itself).
/// - Playback engine → `playbackEngineProvider` overridden with
///   [FakePlaybackEngine] (buildOverrides deliberately does NOT override
///   this provider; only tests do).
/// - Sync engine → `syncServiceProvider` overridden with an idle
///   [_IdleSyncService]. MainShell's initState fires the sync engine with
///   `Connectivity().onConnectivityChanged`, which would touch the
///   connectivity_plus platform channel; the idle subclass makes `start()`
///   a no-op so the channel is never listened to.
/// - package_info_plus → `PackageInfo.setMockInitialValues(...)` (the
///   package's own documented test hook). [WavelyApp] itself never reads
///   `packageInfoProvider` (only the settings screen does, through an
///   `AsyncValue` with a fallback label), so no provider override is
///   needed — the static mock merely keeps `PackageInfo.fromPlatform()`
///   channel-free for any screen that does watch it.
///
/// What is deliberately NOT exercised here: `lib/app/bootstrap.dart` is
/// bypassed because it initializes Sentry from a compile-time DSN and opens
/// the real (filesystem) drift database inside `runZonedGuarded` — neither
/// is fakeable without an SDK. The harness replicates bootstrap's wiring
/// (prefs + db + buildOverrides) minus Sentry, which is a no-op unless a
/// `SENTRY_DSN` dart-define exists anyway. `WavelyEnv.hasSupabase` is a
/// compile-time constant that is `false` in `flutter test` builds (no
/// dart-defines), so the router's auth guard short-circuits and nothing
/// ever touches supabase_flutter initialization.

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/app/providers.dart';
import 'package:wavely/app/wavely_app.dart';
import 'package:wavely/core/constants/app_constants.dart';
import 'package:wavely/core/settings/settings_store.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/sync/sync_providers.dart';
import 'package:wavely/data/sync/sync_service.dart';
import 'package:wavely/design_system/themes/theme_provider.dart'
    show settingsStoreProvider;
import 'package:wavely/features/onboarding/data/onboarding_state.dart';
import 'package:wavely/playback/engines/engine_factory.dart';

import '../support/fake_playback_engine.dart';

/// Everything a test needs to drive or assert against the pumped app.
class WavelyTestHarness {
  const WavelyTestHarness._({
    required this.db,
    required this.prefs,
    required this.engine,
    required this.container,
  });

  /// The in-memory drift database handed to [buildOverrides].
  final AppDatabase db;

  /// The mock-backed SharedPreferences instance handed to
  /// [buildOverrides].
  final SharedPreferences prefs;

  /// The fake engine wired into `playbackEngineProvider`.
  final FakePlaybackEngine engine;

  /// The container the app is mounted on (read providers / notifiers here).
  final ProviderContainer container;

  /// Disposes the container and closes the database. Call from
  /// `addTearDown` / at the end of the test.
  Future<void> tearDown() async {
    container.dispose();
    await db.close();
  }
}

/// Pumps the real [WavelyApp] on a fully-overridden container and returns
/// the harness.
///
/// - [onboardingCompleted]: when true, the `wavely.onboarding.completed`
///   prefs key is pre-seeded so the router redirect lets the shell through
///   (otherwise the app boots into OnboardingFlow).
/// - [locale]: Phase 11 — seeds the settings `localeCode` so `WavelyApp`
///   resolves `AppLocalizations` for the given locale ('en' | 'fa'; pass
///   `Locale('fa')` to drive the full RTL pipeline through the REAL app
///   MaterialApp). Delegates themselves flow from `WavelyApp` — the real
///   root widget already mounts `AppLocalizations.localizationsDelegates`.
/// - [prefsSeed]: additional SharedPreferences values to mock.
/// - [engine]: a custom [FakePlaybackEngine]; a fresh one is created when
///   omitted.
/// - [extraOverrides]: appended after the harness overrides so tests can
///   replace anything else.
/// - [settle]: runs `tester.pumpAndSettle()` after mounting (default true).
/// - [db]: an externally-created [AppDatabase] to mount the app on instead
///   of a fresh in-memory one. Stage 6 E2E fakes (the seeding library
///   scanner) need the SAME database instance the app runs on, and the
///   override list is built before the first pump — so the test creates the
///   database, wires it into its fakes, and hands it in here. The harness
///   `tearDown()` still closes it; the test must not close it too.
Future<WavelyTestHarness> pumpWavelyApp(
  WidgetTester tester, {
  bool onboardingCompleted = false,
  Locale? locale,
  Map<String, Object> prefsSeed = const <String, Object>{},
  FakePlaybackEngine? engine,
  List<Override> extraOverrides = const <Override>[],
  bool settle = true,
  AppDatabase? db,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SharedPreferences: the package's own mock; must be installed before
  // the first `SharedPreferences.getInstance()`.
  SharedPreferences.setMockInitialValues(<String, Object>{
    ...prefsSeed,
    if (onboardingCompleted) OnboardingDraft.prefsCompletedKey: 'true',
    // Phase 11: seed the locale through the canonical settings key so
    // `localeProvider` (and thus WavelyApp's MaterialApp) picks it up.
    if (locale != null)
      '${AppConstants.settingsKeyPrefix}localeCode': locale.languageCode,
  });
  final prefs = await SharedPreferences.getInstance();

  // package_info_plus: package-provided mock so `PackageInfo.fromPlatform()`
  // resolves without a platform channel (see file header).
  PackageInfo.setMockInitialValues(
    appName: 'Wavely',
    packageName: 'dev.wavely.test',
    version: '0.1.0',
    buildNumber: '1',
    buildSignature: 'test',
  );

  final AppDatabase effectiveDb = db ?? AppDatabase(NativeDatabase.memory());
  final fakeEngine = engine ?? FakePlaybackEngine();

  final container = ProviderContainer(
    overrides: <Override>[
      ...buildOverrides(db: effectiveDb, prefs: prefs),
      playbackEngineProvider.overrideWithValue(fakeEngine),
      // MainShell starts the sync engine on first build; the idle service
      // keeps the connectivity_plus channel out of the test.
      syncServiceProvider.overrideWith(
        (ref) => _IdleSyncService(
          effectiveDb,
          ref.watch(settingsStoreProvider),
        ),
      ),
      ...extraOverrides,
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const WavelyApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }

  return WavelyTestHarness._(
    db: effectiveDb,
    prefs: prefs,
    engine: fakeEngine,
    container: container,
  );
}

/// Sync engine that never starts: same construction as the real provider
/// (memory db + real store, no Supabase backend) but `start()` is a no-op
/// so `Connectivity().onConnectivityChanged` is never subscribed in tests.
class _IdleSyncService extends SyncService {
  _IdleSyncService(AppDatabase db, SettingsStore store)
      : super(
          db: db,
          outboxDao: db.syncOutboxDao,
          playsDao: db.playsDao,
          tracksDao: db.tracksDao,
          settingsStore: store,
          backend: null, // WavelyEnv.hasSupabase is false in tests anyway.
        );

  @override
  Future<void> start({Stream<bool>? connectivityChanges}) async {}
}
