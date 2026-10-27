/// Authored, awaiting local run (Task 2-a).
///
/// Tests for `lib/core/config/env.dart` — [WavelyEnv], the typed accessor
/// over compile-time `String.fromEnvironment` values.
///
/// SCOPE: `flutter test` compiles WITHOUT `--dart-define`s, so every env
/// constant is the empty string — this suite pins the no-.env default
/// build (all getters null, all feature flags false). The non-empty
/// branches of the `_has` logic are compile-time constants and cannot be
/// exercised without recompiling with dart-defines; they are documented
/// here as untestable in this harness rather than faked around.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/config/env.dart';

void main() {
  group('WavelyEnv defaults (no dart-defines in the test build)', () {
    test('Supabase keys are absent', () {
      expect(WavelyEnv.supabaseUrl, isNull);
      expect(WavelyEnv.supabaseAnonKey, isNull);
      expect(WavelyEnv.hasSupabase, isFalse);
    });

    test('Telegram bot is absent', () {
      expect(WavelyEnv.telegramBotUsername, isNull);
      expect(WavelyEnv.hasTelegramBot, isFalse);
    });

    test('AI provider keys are absent', () {
      expect(WavelyEnv.geminiApiKey, isNull);
      expect(WavelyEnv.openAiApiKey, isNull);
      // hasAiProvider is an OR of the two keys — false only when both are
      // missing, which the default build guarantees.
      expect(WavelyEnv.hasAiProvider, isFalse);
    });

    test('metadata API client ids are absent', () {
      expect(WavelyEnv.spotifyClientId, isNull);
      expect(WavelyEnv.hasSpotify, isFalse);
      expect(WavelyEnv.jamendoClientId, isNull);
      expect(WavelyEnv.hasJamendo, isFalse);
    });
  });

  group('WavelyEnv contract notes (compile-time semantics)', () {
    test('values are stable across repeated reads within a build', () {
      // String.fromEnvironment is baked in at compile time; repeated reads
      // must return identical results (guards against someone swapping a
      // const for a runtime lookup mid-session).
      final url1 = WavelyEnv.supabaseUrl;
      final url2 = WavelyEnv.supabaseUrl;
      final has1 = WavelyEnv.hasSupabase;
      final has2 = WavelyEnv.hasSupabase;
      expect(url1, equals(url2));
      expect(has1, equals(has2));
    });

    test('flags are plain bools, never null', () {
      // The contract: features check flags, never null-string juggling.
      // (isFalse/isTrue assertions in the group above cover the default
      // values; this asserts the TYPE contract via a bool-typed local.)
      const bool hasSupabase = WavelyEnv.hasSupabase;
      const bool hasAiProvider = WavelyEnv.hasAiProvider;
      const bool hasTelegramBot = WavelyEnv.hasTelegramBot;
      const bool hasSpotify = WavelyEnv.hasSpotify;
      const bool hasJamendo = WavelyEnv.hasJamendo;
      expect(hasSupabase, isA<bool>());
      expect(hasAiProvider, isA<bool>());
      expect(hasTelegramBot, isA<bool>());
      expect(hasSpotify, isA<bool>());
      expect(hasJamendo, isA<bool>());
    });
  });
}
