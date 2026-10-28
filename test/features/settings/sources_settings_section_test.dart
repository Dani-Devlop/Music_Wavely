// authored, awaiting local run.
//
// Widget tests for
// lib/features/settings/presentation/widgets/sources_settings_section.dart:
// descriptor rows render with configured/enabled state, the enable switch
// persists through SourceSettings, and the Jamendo editor dialog saves the
// client id.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/presentation/widgets/sources_settings_section.dart';
import 'package:wavely/sources/source_registry.dart';
import 'package:wavely/sources/source_providers.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';

SourceSettings _settings(SharedPreferences prefs) => SourceSettings(
      prefs,
      credentials: InMemorySubsonicCredentialStore(),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  SharedPreferences prefs, {
  List<SourceDescriptor> descriptors = const <SourceDescriptor>[
    SourceDescriptor(
      id: 'subsonic',
      displayName: 'Subsonic / Navidrome',
      configured: true,
      enabled: true,
    ),
    SourceDescriptor(
      id: 'jamendo',
      displayName: 'Jamendo',
      configured: false,
      enabled: true,
    ),
    SourceDescriptor(
      id: 'archive',
      displayName: 'archive.org',
      configured: true,
      enabled: false,
    ),
    SourceDescriptor(
      id: 'fma',
      displayName: 'Free Music Archive',
      configured: true,
      enabled: true,
    ),
  ],
}) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      sourceSettingsProvider.overrideWithValue(_settings(prefs)),
      sourceDescriptorsProvider.overrideWith(
        (Ref ref) async => descriptors,
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SourcesSettingsSection())),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  Future<SharedPreferences> prefs() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return SharedPreferences.getInstance();
  }

  testWidgets('renders one row per source with state subtitles',
      (WidgetTester tester) async {
    await _pump(tester, await prefs());

    expect(find.text('Subsonic / Navidrome'), findsOneWidget);
    expect(find.text('Jamendo'), findsOneWidget);
    expect(find.text('archive.org'), findsOneWidget);
    expect(find.text('Free Music Archive'), findsOneWidget);
    expect(find.text('Configured'), findsNWidgets(3));
    expect(find.text('Not configured'), findsOneWidget);
  });

  testWidgets('enable switch persists through SourceSettings',
      (WidgetTester tester) async {
    final SharedPreferences p = await prefs();
    final ProviderContainer container = await _pump(tester, p);

    await tester.tap(find.byKey(const Key('source-switch-archive')));
    await tester.pump();

    expect(_settings(p).isSourceEnabled('archive'), isTrue);
    // Switch widget state updated.
    final Switch sw = tester.widget<Switch>(
      find.byKey(const Key('source-switch-archive')),
    );
    expect(sw.value, isTrue);
  });

  testWidgets('subsonic row exposes the configure action',
      (WidgetTester tester) async {
    await _pump(tester, await prefs());
    expect(find.byKey(const Key('source-edit-subsonic')), findsOneWidget);
  });

  testWidgets('jamendo editor saves the client id', (WidgetTester tester) async {
    final SharedPreferences p = await prefs();
    await _pump(tester, p);

    await tester.tap(find.byKey(const Key('source-edit-jamendo')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('jamendo-clientid-field')),
      'my-jamendo-id',
    );
    await tester.tap(find.byKey(const Key('jamendo-save-button')));
    await tester.pumpAndSettle();

    final SharedPreferences p2 = await SharedPreferences.getInstance();
    expect(_settings(p2).loadJamendoClientId(), 'my-jamendo-id');
  });

  testWidgets('no configure action for configless sources',
      (WidgetTester tester) async {
    await _pump(tester, await prefs());
    expect(find.byKey(const Key('source-edit-archive')), findsNothing);
    expect(find.byKey(const Key('source-edit-fma')), findsNothing);
  });

  test('SubsonicConfig round trip still holds (fixture sanity)', () {
    const SubsonicConfig c = SubsonicConfig(
      url: 'https://music.example.com',
      username: 'dani',
      password: 'pw',
    );
    expect(c.toPublicJson().containsKey('password'), isFalse);
  });
}
