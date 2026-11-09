/// Widget test of the Phase 8 `AudioSettingsScreen`.
///
/// Hermetic harness: in-memory Drift + a pre-initialized
/// [AudioEngineController] (no engine → capability hints degrade) +
/// the production scan-service provider bound to the same memory DB.
/// Verifies section rendering, the 5-band sliders, the effects controls
/// and the ReplayGain mode segmented button drive the controller state.
///
/// Pumping note: the screen's generous ListView cacheExtent builds every
/// section within the first two frames; tests pump explicitly instead of
/// `pumpAndSettle` (settling re-lays-out lazily and disposes the far
/// children in this harness).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/design_system/design_system.dart';
import 'package:wavely/features/settings/presentation/screens/audio_settings_screen.dart';
import 'package:wavely/l10n/app_localizations.dart';
import 'package:wavely/playback/profiles/audio_engine_controller.dart';
import 'package:wavely/playback/replaygain/replay_gain_math.dart';

void main() {
  testWidgets('renders every section and reflects controller state',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed a profile so the screen has state to show.
    final AudioEngineController controller = _buildController(db);
    await controller.init();
    await controller.setBassBoost(40);

    final ProviderContainer container = _container(db, controller);

    // Tall surface: the whole settings content fits on screen, so every
    // section is built and hittable (no scroll bookkeeping).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: WavelyThemes.dark(WavelyAccent.purple.colors),
          home: const AudioSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Every section is in the tree (cacheExtent keeps them built).
    // v1.0.2: Musicolet-parity green section headers render uppercase.
    expect(find.text('OUTPUT PROFILE'), findsOneWidget);
    expect(find.text('DECODER'), findsOneWidget);
    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.text('EQUALIZER'), findsOneWidget);
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(find.text('REPLAYGAIN'), findsOneWidget);
    expect(find.text('TRANSITIONS'), findsOneWidget);

    // The five band sliders exist.
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey<String>('eq-band-$i')), findsOneWidget);
    }

    // Effects controls reflect the seeded bass boost.
    expect(find.text('40%'), findsOneWidget);

    // ReplayGain mode control exists with the three options.
    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);

    // Transitions controls exist.
    expect(find.text('Gapless playback'), findsOneWidget);
  });

  testWidgets('toggling ReplayGain mode commits the profile',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final AudioEngineController controller = _buildController(db);
    await controller.init();

    final ProviderContainer container = _container(db, controller);

    // Tall surface: the whole settings content fits on screen, so every
    // section is built and hittable (no scroll bookkeeping).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: WavelyThemes.dark(WavelyAccent.purple.colors),
          home: const AudioSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final Finder trackSegment = find.text('Track');
    await tester.ensureVisible(trackSegment);
    await tester.pump();
    await tester.tap(trackSegment);
    await tester.pump();

    expect(controller.state.settings.replayGainMode, ReplayGainMode.track);
  });

  testWidgets('force-mono switch commits the effect',
      (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final AudioEngineController controller = _buildController(db);
    await controller.init();

    final ProviderContainer container = _container(db, controller);

    // Tall surface: the whole settings content fits on screen, so every
    // section is built and hittable (no scroll bookkeeping).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: WavelyThemes.dark(WavelyAccent.purple.colors),
          home: const AudioSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final Finder monoSwitch =
        find.byKey(const ValueKey<String>('effect-mono'));
    await tester.ensureVisible(monoSwitch);
    await tester.pump();
    await tester.tap(monoSwitch, warnIfMissed: false);
    await tester.pump();

    expect(controller.state.settings.effects.forceMono, isTrue);
    // And the value was persisted.
    final List<AudioProfileRowLike> stored = await controller.storedProfiles();
    expect(stored, isNotEmpty);
    expect(
      stored.firstWhere((row) => row.outputDeviceId == 'default').forceMono,
      isTrue,
    );
  });
}

ProviderContainer _container(AppDatabase db, AudioEngineController controller) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      audioEngineControllerProvider.overrideWith((Ref ref) => controller),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Row type alias keeping the assertion readable (the concrete row class
/// comes from the generated Drift code).
typedef AudioProfileRowLike = dynamic;

AudioEngineController _buildController(AppDatabase db) {
  // The controller is exercised through its real behavior; the engine
  // indirection returns nothing (no engine = capability flags false, the
  // screen degrades to "not supported" hints — exactly the parity path).
  return AudioEngineController(
    db: db,
    deviceKeyFuture: Future<String>.value('test-device'),
    engineRef: () => null,
  );
}
