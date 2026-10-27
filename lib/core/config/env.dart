/// Typed accessor over environment configuration.
///
/// Strategy (Stage 1.2): compile-time `String.fromEnvironment` fed by
/// `flutter run --dart-define-from-file=.env` (official Flutter feature;
/// `.env` uses plain KEY=VALUE lines — same template as `.env.example`).
///
/// Rules:
/// - No `.env` file is required to BUILD; running without the define flag
///   yields empty strings and every feature degrades gracefully (the local
///   player core keeps working).
/// - Keys are optional BY DESIGN — no Stage 1.2 feature may hard-require a
///   key except through its own feature-flag check ([WavelyEnv.hasSupabase],
///   [WavelyEnv.hasAiProvider], ...).
/// - Values are compile-time constants; they are never logged — only
///   feature flags derived from them are surfaced.
abstract final class WavelyEnv {
  static const String _supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _telegramBotUsername =
      String.fromEnvironment('TELEGRAM_BOT_USERNAME');
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _openAiApiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String _spotifyClientId =
      String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const String _jamendoClientId =
      String.fromEnvironment('JAMENDO_CLIENT_ID');

  static bool _has(String value) => value.trim().isNotEmpty;

  // -- Supabase -------------------------------------------------------------

  static String? get supabaseUrl => _has(_supabaseUrl) ? _supabaseUrl : null;
  static String? get supabaseAnonKey =>
      _has(_supabaseAnonKey) ? _supabaseAnonKey : null;
  static bool get hasSupabase =>
      _has(_supabaseUrl) && _has(_supabaseAnonKey);

  // -- Telegram bot ----------------------------------------------------------

  static String? get telegramBotUsername =>
      _has(_telegramBotUsername) ? _telegramBotUsername : null;
  static bool get hasTelegramBot => _has(_telegramBotUsername);

  // -- AI providers -----------------------------------------------------------

  static String? get geminiApiKey => _has(_geminiApiKey) ? _geminiApiKey : null;
  static String? get openAiApiKey => _has(_openAiApiKey) ? _openAiApiKey : null;
  static bool get hasAiProvider => _has(_geminiApiKey) || _has(_openAiApiKey);

  // -- Metadata-only official APIs -------------------------------------------

  static String? get spotifyClientId =>
      _has(_spotifyClientId) ? _spotifyClientId : null;
  static bool get hasSpotify => _has(_spotifyClientId);

  static String? get jamendoClientId =>
      _has(_jamendoClientId) ? _jamendoClientId : null;
  static bool get hasJamendo => _has(_jamendoClientId);
}
