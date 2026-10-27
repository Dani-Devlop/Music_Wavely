import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavely/core/settings/settings_store.dart';

/// [SettingsStore] backed by SharedPreferences (real app bootstrap).
///
/// Semantics (documented contract):
/// - `write` maps every supported primitive to its SharedPreferences
///   setter; writing `null` REMOVES the key; value types outside the
///   supported set are ignored (this store is a flat key/value shelf, not a
///   typed document DB — callers only persist primitives by design).
/// - `read` dispatches on the static type `T`; a missing key resolves to
///   null so callers keep their defaults. SharedPreferences also returns
///   null on an internal type mismatch (e.g. reading `double` for a value
///   stored as `int`), which surfaces here as a `null` result as well.
class SharedPreferencesSettingsStore implements SettingsStore {
  /// Creates the store over [prefs].
  const SharedPreferencesSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<void> write(String key, Object? value) async {
    switch (value) {
      case final String v:
        await _prefs.setString(key, v);
      case final int v:
        await _prefs.setInt(key, v);
      case final bool v:
        await _prefs.setBool(key, v);
      case final double v:
        await _prefs.setDouble(key, v);
      case final List<String> v:
        await _prefs.setStringList(key, v);
      case null:
        await _prefs.remove(key);
      default:
        // Unsupported value type — intentionally ignored (see class doc).
        break;
    }
  }

  @override
  Future<T?> read<T>(String key) async {
    final Object? value = switch (T) {
      const (String) => _prefs.getString(key),
      const (int) => _prefs.getInt(key),
      const (bool) => _prefs.getBool(key),
      const (double) => _prefs.getDouble(key),
      const (List<String>) => _prefs.getStringList(key),
      _ => null,
    };
    if (value is T) {
      return value;
    }
    return null;
  }
}
