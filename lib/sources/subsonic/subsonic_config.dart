import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Connection settings for a Subsonic-compatible server (Subsonic,
/// Navidrome, Airsonic, Gonic, ...).
///
/// Only non-secret fields live in plain storage (SharedPreferences JSON via
/// the source registry); the password goes through
/// [SubsonicCredentialStore], which defaults to `flutter_secure_storage`
/// (Keychain / Keystore / libsecret). Tests swap in an in-memory store.
class SubsonicConfig {
  /// Creates a connection config.
  const SubsonicConfig({
    required this.url,
    required this.username,
    required this.password,
    this.apiVersion = defaultApiVersion,
    this.enabled = true,
  });

  /// Subsonic REST API version Wavely speaks (v1.16.1 per Stage 2.1 spec).
  static const String defaultApiVersion = '1.16.1';

  /// Client identifier sent as the `c` parameter.
  static const String clientName = 'wavely';

  /// Base URL of the server, e.g. `https://music.example.com`.
  final String url;

  /// Server username.
  final String username;

  /// Server password (kept out of plain storage by the credential store).
  final String password;

  /// API version negotiated with the server.
  final String apiVersion;

  /// Whether the source participates in unified search / playback.
  final bool enabled;

  /// Trimmed base URL without a trailing slash (normalises user input).
  String get baseUrl {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Copy with replaced fields.
  SubsonicConfig copyWith({
    String? url,
    String? username,
    String? password,
    String? apiVersion,
    bool? enabled,
  }) =>
      SubsonicConfig(
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        apiVersion: apiVersion ?? this.apiVersion,
        enabled: enabled ?? this.enabled,
      );

  /// Non-secret projection persisted in SharedPreferences.
  Map<String, dynamic> toPublicJson() => <String, dynamic>{
        'url': url,
        'username': username,
        'apiVersion': apiVersion,
        'enabled': enabled,
      };

  /// Rebuilds the non-secret part; the password comes from
  /// [SubsonicCredentialStore.read] separately.
  static SubsonicConfig fromPublicJson(
    Map<String, dynamic> json, {
    String password = '',
  }) =>
      SubsonicConfig(
        url: (json['url'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: password,
        apiVersion: (json['apiVersion'] as String?) ?? defaultApiVersion,
        enabled: (json['enabled'] as bool?) ?? true,
      );

  /// True when both base URL and username are present (password may be
  /// empty for token-less public servers during a ping).
  bool get isComplete => baseUrl.isNotEmpty && username.trim().isNotEmpty;
}

/// Abstracts password persistence so tests never touch platform channels.
abstract class SubsonicCredentialStore {
  /// Reads the stored password, or `null` when absent.
  Future<String?> read();

  /// Persists the password.
  Future<void> write(String password);

  /// Removes the stored password.
  Future<void> delete();
}

/// `flutter_secure_storage`-backed credential store.
class SecureSubsonicCredentialStore implements SubsonicCredentialStore {
  /// Creates the store under the given [key].
  SecureSubsonicCredentialStore({String key = 'wavely.subsonic.password'})
      : _key = key;

  final String _key;

  static const AndroidOptions _android = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _android,
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String password) =>
      _storage.write(key: _key, value: password);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// In-memory credential store for tests and for the "not configured" state.
class InMemorySubsonicCredentialStore implements SubsonicCredentialStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String password) async {
    _value = password;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}

/// Optional Supabase Vault sync (encrypted at rest, additive only — does not
/// modify existing sync tables; the secret is stored as a Vault secret keyed
/// by a stable key, never in a plain table).
///
/// The Vault RPC lives in the owner's Supabase project; when the RPC is
/// absent the sync is a no-op failure (returns false) and the local secure
/// store remains the source of truth. Authored, awaiting local run.
abstract class VaultCredentialSync {
  /// Best-effort push of [password]; returns false instead of throwing.
  Future<bool> push(String password);

  /// Best-effort pull; returns `null` instead of throwing.
  Future<String?> pull();
}
