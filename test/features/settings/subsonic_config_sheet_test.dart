// authored, awaiting local run.
//
// Widget tests for
// lib/features/settings/presentation/widgets/subsonic_config_sheet.dart:
// field rendering, "Test connection" against an unreachable server shows
// the honest failure, Save persists via SourceSettings (+ secure store),
// and Remove clears config + secret.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';
import 'package:wavely/features/settings/presentation/widgets/subsonic_config_sheet.dart';
import 'package:wavely/sources/source_providers.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';

class _InMemoryStore implements SubsonicCredentialStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String password) async {
    value = password;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

Future<(ProviderContainer, _InMemoryStore)> _pump(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final _InMemoryStore store = _InMemoryStore();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPrefsProvider.overrideWithValue(prefs),
      sourceSettingsProvider.overrideWithValue(
        SourceSettings(prefs, credentials: store),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => SubsonicConfigSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (container, store);
}

void main() {
  testWidgets('renders url / username / password fields and actions',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('subsonic-url-field')), findsOneWidget);
    expect(find.byKey(const Key('subsonic-username-field')), findsOneWidget);
    expect(find.byKey(const Key('subsonic-password-field')), findsOneWidget);
    expect(find.byKey(const Key('subsonic-test-button')), findsOneWidget);
    expect(find.byKey(const Key('subsonic-save-button')), findsOneWidget);
    expect(find.byKey(const Key('subsonic-remove-button')), findsOneWidget);
  });

  testWidgets('test connection against an unreachable server reports the '
      'failure honestly', (WidgetTester tester) async {
    await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('subsonic-url-field')),
      'https://127.0.0.1:1',
    );
    await tester.enterText(
      find.byKey(const Key('subsonic-username-field')),
      'dani',
    );
    await tester.enterText(
      find.byKey(const Key('subsonic-password-field')),
      'pw',
    );
    await tester.tap(find.byKey(const Key('subsonic-test-button')));
    // Dio connection error against a closed port resolves quickly; give
    // the future a bounded window.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.textContaining('Failed:'), findsOneWidget);
  });

  testWidgets('save persists the config and the password in the secure '
      'store, then closes the sheet', (WidgetTester tester) async {
    final (ProviderContainer container, _InMemoryStore store) =
        await _pump(tester);

    await tester.enterText(
      find.byKey(const Key('subsonic-url-field')),
      'https://music.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('subsonic-username-field')),
      'dani',
    );
    await tester.enterText(
      find.byKey(const Key('subsonic-password-field')),
      's3cret',
    );
    await tester.tap(find.byKey(const Key('subsonic-save-button')));
    await tester.pumpAndSettle();

    final SourceSettings settings = container.read(sourceSettingsProvider);
    final SubsonicConfig? config = await settings.loadSubsonic();
    expect(config, isNotNull);
    expect(config!.url, 'https://music.example.com');
    expect(config.username, 'dani');
    expect(config.password, 's3cret');
    expect(store.value, 's3cret');

    // Sheet closed.
    expect(find.byKey(const Key('subsonic-save-button')), findsNothing);
  });

  testWidgets('remove clears the config and the stored secret',
      (WidgetTester tester) async {
    final (ProviderContainer container, _InMemoryStore store) =
        await _pump(tester);
    final SourceSettings settings = container.read(sourceSettingsProvider);
    await settings.saveSubsonic(
      const SubsonicConfig(
        url: 'https://x',
        username: 'u',
        password: 'old',
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('subsonic-remove-button')));
    await tester.pumpAndSettle();

    expect(await settings.loadSubsonic(), isNull);
    expect(store.value, isNull);
  });
}
