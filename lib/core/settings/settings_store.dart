/// Storage abstraction for app settings (theme, playback prefs, ...).
///
/// Implementations wrap SharedPreferences, secure storage or plain maps in
/// tests; keys are plain strings (see `AppConstants.settingsKeyPrefix`).
abstract class SettingsStore {
  const SettingsStore();

  Future<void> write(String key, Object? value);

  Future<T?> read<T>(String key);
}

/// Ephemeral in-memory [SettingsStore] used by tests and as the default
/// binding until a real persistence layer is wired in.
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore({Map<String, Object?>? initial})
      : _map = initial == null
            ? <String, Object?>{}
            : Map<String, Object?>.of(initial);

  final Map<String, Object?> _map;

  @override
  Future<void> write(String key, Object? value) async {
    _map[key] = value;
  }

  @override
  Future<T?> read<T>(String key) async {
    final value = _map[key];
    if (value is T) {
      return value;
    }
    return null;
  }
}
