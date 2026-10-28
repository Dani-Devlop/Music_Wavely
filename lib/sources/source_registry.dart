import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wavely/domain/repositories/source_provider.dart';
import 'package:wavely/sources/archive_org/archive_org_source.dart';
import 'package:wavely/sources/fma/fma_source.dart';
import 'package:wavely/sources/jamendo/jamendo_source.dart';
import 'package:wavely/sources/subsonic/subsonic_config.dart';
import 'package:wavely/sources/subsonic/subsonic_source.dart';

/// Persistence + construction of the Stage 2.1 online sources.
///
/// Non-secret settings live in SharedPreferences under `sources.*` keys;
/// the Subsonic password lives in a [SubsonicCredentialStore]
/// (flutter_secure_storage in production, in-memory in tests).
class SourceSettings {
  /// Creates settings over [prefs]; [credentials] defaults to the secure
  /// store.
  SourceSettings(this._prefs, {SubsonicCredentialStore? credentials})
      : _credentials = credentials ?? SecureSubsonicCredentialStore();

  static const String _kSubsonic = 'sources.subsonic.config';
  static const String _kJamendo = 'sources.jamendo.clientId';
  static const String _kEnabledPrefix = 'sources.enabled.';

  final SharedPreferences _prefs;
  final SubsonicCredentialStore _credentials;

  /// Credential store (exposed for the config sheet's save flow).
  SubsonicCredentialStore get credentials => _credentials;

  // --- Subsonic -----------------------------------------------------------

  /// Loads the Subsonic config, merging the secure password, or `null` when
  /// not configured.
  Future<SubsonicConfig?> loadSubsonic() async {
    final String? raw = _prefs.getString(_kSubsonic);
    if (raw == null) {
      return null;
    }
    final Object? decoded = _decodeJson(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final String? password = await _credentials.read();
    final SubsonicConfig config = SubsonicConfig.fromPublicJson(
      decoded,
      password: password ?? '',
    );
    return config.isComplete ? config : null;
  }

  /// Persists the config: public fields to SharedPreferences, the password
  /// to the credential store (empty password deletes the secret).
  Future<void> saveSubsonic(SubsonicConfig config) async {
    await _prefs.setString(_kSubsonic, _encodeJson(config.toPublicJson()));
    if (config.password.isEmpty) {
      await _credentials.delete();
    } else {
      await _credentials.write(config.password);
    }
  }

  /// Removes the Subsonic config and its stored password.
  Future<void> clearSubsonic() async {
    await _prefs.remove(_kSubsonic);
    await _credentials.delete();
  }

  // --- Jamendo ------------------------------------------------------------

  /// Jamendo application client id, or `null` when unset.
  String? loadJamendoClientId() => _prefs.getString(_kJamendo);

  /// Persists (or clears with `null`) the Jamendo client id.
  Future<void> saveJamendoClientId(String? clientId) async {
    if (clientId == null || clientId.trim().isEmpty) {
      await _prefs.remove(_kJamendo);
    } else {
      await _prefs.setString(_kJamendo, clientId.trim());
    }
  }

  // --- Enable flags -------------------------------------------------------

  /// Whether [sourceId] is enabled (default true for all four sources).
  bool isSourceEnabled(String sourceId) =>
      _prefs.getBool('$_kEnabledPrefix$sourceId') ?? true;

  /// Persists the enable flag for [sourceId].
  Future<void> setSourceEnabled(String sourceId, bool enabled) =>
      _prefs.setBool('$_kEnabledPrefix$sourceId', enabled);

  static Object? _decodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } on Object {
      return null;
    }
  }

  static String _encodeJson(Map<String, dynamic> json) =>
      jsonEncode(json);
}

/// Builds [SourceProvider] instances from [SourceSettings].
class SourceRegistry {
  /// Creates the registry over [settings]; [dio] is shared by all sources
  /// (injectable for tests).
  SourceRegistry(this._settings, {Dio? dio}) : _dioFactory = dio;

  final SourceSettings _settings;
  final Dio? _dioFactory;

  /// Descriptors for the settings UI (id, display name, availability).
  Future<List<SourceDescriptor>> describeAll() async {
    final SubsonicConfig? subsonic = await _settings.loadSubsonic();
    return <SourceDescriptor>[
      SourceDescriptor(
        id: subsonicId,
        displayName: 'Subsonic / Navidrome',
        configured: subsonic != null,
        enabled: _settings.isSourceEnabled(subsonicId),
      ),
      SourceDescriptor(
        id: JamendoSource.sourceId,
        displayName: 'Jamendo',
        configured: _settings.loadJamendoClientId() != null,
        enabled: _settings.isSourceEnabled(JamendoSource.sourceId),
      ),
      SourceDescriptor(
        id: ArchiveOrgSource.sourceId,
        displayName: 'archive.org',
        configured: true,
        enabled: _settings.isSourceEnabled(ArchiveOrgSource.sourceId),
      ),
      SourceDescriptor(
        id: FmaSource.sourceId,
        displayName: 'Free Music Archive',
        configured: true,
        enabled: _settings.isSourceEnabled(FmaSource.sourceId),
      ),
    ];
  }

  /// Instantiates every configured + enabled source.
  Future<List<SourceProvider>> resolveEnabled() async {
    final List<SourceProvider> out = <SourceProvider>[];
    final SubsonicConfig? subsonic = await _settings.loadSubsonic();
    if (subsonic != null && _settings.isSourceEnabled(subsonicId)) {
      out.add(SubsonicSource(config: subsonic, dio: _dioFactory));
    }
    final String? jamendoId = _settings.loadJamendoClientId();
    if (jamendoId != null && _settings.isSourceEnabled(jamendoSourceId)) {
      out.add(
        JamendoSource(clientId: jamendoId, dio: _dioFactory),
      );
    }
    if (_settings.isSourceEnabled(archiveId)) {
      out.add(ArchiveOrgSource(dio: _dioFactory));
    }
    if (_settings.isSourceEnabled(fmaId)) {
      out.add(FmaSource(dio: _dioFactory));
    }
    return out;
  }

  /// Builds one configured source by id (used by the "Test connection"
  /// button), or `null` when that source is not configured.
  Future<SourceProvider?> buildById(String sourceId) async {
    final List<SourceProvider> enabled = await resolveEnabled();
    for (final SourceProvider s in enabled) {
      if (s.id == sourceId) {
        return s;
      }
    }
    return null;
  }
}

/// Canonical source ids (kept as top-level constants so tests and the UI
/// share one spelling).
const String subsonicId = 'subsonic';
const String jamendoSourceId = 'jamendo';
const String archiveId = 'archive';
const String fmaId = 'fma';

/// Human-readable summary row for the settings UI.
class SourceDescriptor {
  /// Creates a descriptor.
  const SourceDescriptor({
    required this.id,
    required this.displayName,
    required this.configured,
    required this.enabled,
  });

  /// Source id ([SourceProvider.id]).
  final String id;

  /// Display name for the row.
  final String displayName;

  /// True when the source has the credentials it needs.
  final bool configured;

  /// True when the user enabled the source.
  final bool enabled;
}
