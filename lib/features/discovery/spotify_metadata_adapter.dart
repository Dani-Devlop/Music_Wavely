import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:wavely/core/config/env.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';
import 'package:wavely/data/remote/metadata_http.dart';

/// One Spotify track (METADATA ONLY — no playback, no downloads).
class SpotifyTrack {
  /// Creates a track row.
  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artistName,
    this.albumName,
  });

  /// Spotify track id.
  final String id;

  /// Track title.
  final String name;

  /// Primary artist name (first of the `artists` array).
  final String artistName;

  /// Album name when present.
  final String? albumName;
}

/// OAuth2 tokens from the Spotify accounts service.
class SpotifyCredentials {
  /// Creates credentials.
  const SpotifyCredentials({
    required this.accessToken,
    required this.expiresInSeconds,
    this.refreshToken,
  });

  /// Bearer token for Web API calls.
  final String accessToken;

  /// Token lifetime in seconds (falls back to 3600 when malformed).
  final int expiresInSeconds;

  /// Refresh token when Spotify issues one (public-scope flows may not).
  final String? refreshToken;
}

/// Spotify Web API metadata adapter (Stage 1.2, optional feature).
///
/// FEATURE GATE: only used when [available] (`WavelyEnv.hasSpotify`, i.e.
/// `SPOTIFY_CLIENT_ID` in .env) is true. Without the dart-define the
/// class is never constructed and every call site stays on the
/// MusicBrainz/Deezer path.
///
/// SCOPE: metadata only — `searchTrack` reads the public catalog via
/// `GET https://api.spotify.com/v1/search?type=track` (6 h cache). No
/// playback, no library writes, no downloads.
///
/// AUTH (OAuth2 Authorization Code + PKCE, no client secret):
/// 1. [generateCodeVerifier] + [codeChallenge] (S256).
/// 2. [authorize] builds the authorize URL and opens it externally via
///    url_launcher (`LaunchMode.externalApplication`).
/// 3. Spotify redirects to [redirectUri] with `?code=...` — see the
///    TODO on [receiveCredentials]: the app-link host must be configured
///    per platform before that redirect can land; the code exchange
///    itself is fully implemented.
///
/// Every method returns a [Result] and never throws. The raw (non-
/// caching) http client used for the token POST is injectable for tests.
class SpotifyMetadataClient {
  /// Creates the adapter; [clientId] falls back to [WavelyEnv].
  SpotifyMetadataClient({
    required CachingHttpClient http,
    String? clientId,
    Future<bool> Function(Uri url)? launchExternal,
    http.Client? rawClient,
  })  : _http = http,
        _clientId = clientId ?? WavelyEnv.spotifyClientId,
        _launchExternal = launchExternal ?? _defaultLaunch,
        _injectedRaw = rawClient;

  /// Feature gate mirroring `WavelyEnv.hasSpotify`.
  static bool get available => WavelyEnv.hasSpotify;

  /// Deep-link redirect target.
  ///
  /// TODO(verify): this scheme+host must be registered as an app link /
  /// custom scheme on EVERY target platform before the OAuth redirect
  /// can reach the app; until then [receiveCredentials] stays reachable
  /// only for tests/manual token pasting.
  static const String redirectUri = 'wavely://oauth/spotify';

  static const String _authorizeEndpoint =
      'https://accounts.spotify.com/authorize';
  static const String _tokenEndpoint =
      'https://accounts.spotify.com/api/token';
  static const String _searchEndpoint = 'https://api.spotify.com/v1/search';
  static const int _verifierBytes = 64;

  final CachingHttpClient _http;
  final String? _clientId;
  final Future<bool> Function(Uri url) _launchExternal;
  final http.Client? _injectedRaw;
  http.Client? _lazyRaw;

  /// Raw (non-caching) client for the token endpoint POST only. Created
  /// lazily in a getter because the constructor parameter `http` (the
  /// caching client) would shadow the `http:` import prefix inside the
  /// initializer list.
  http.Client get _raw => _injectedRaw ?? (_lazyRaw ??= http.Client());

  static Future<bool> _defaultLaunch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  /// Random PKCE code_verifier (64 random bytes, base64url, unpadded).
  String generateCodeVerifier() {
    final random = Random.secure();
    final bytes =
        List<int>.generate(_verifierBytes, (_) => random.nextInt(256));
    return _base64UrlNoPad(bytes);
  }

  /// S256 code_challenge for [verifier] (sha256 → base64url, unpadded).
  String codeChallenge(String verifier) => _base64UrlNoPad(
        crypto.sha256.convert(utf8.encode(verifier)).bytes,
      );

  /// Builds the authorize URL (does NOT launch anything).
  Result<Uri> buildAuthorizeUrl({
    required String codeVerifier,
    String? state,
  }) {
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) {
      return const Result<Uri>.err(
        Failure.permission(
          message: 'Spotify client id missing (set SPOTIFY_CLIENT_ID)',
        ),
      );
    }
    final url =
        Uri.parse(_authorizeEndpoint).replace(queryParameters: <String, String>{
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge(codeVerifier),
      if (state != null) 'state': state,
    });
    return Result<Uri>.success(url);
  }

  /// Opens the authorize URL in the external browser. Never throws.
  Future<Result<void>> authorize({
    required String codeVerifier,
    String? state,
  }) {
    return buildAuthorizeUrl(codeVerifier: codeVerifier, state: state)
        .flatMap((url) async {
      try {
        final launched = await _launchExternal(url);
        return launched
            ? const Result<void>.success(null)
            : const Result<void>.err(
                Failure.unknown(message: 'No external browser available'),
              );
      } on Object catch (error) {
        return Result<void>.err(
          Failure.unknown(message: 'Could not open browser', cause: error),
        );
      }
    });
  }

  /// Exchanges the authorization [code] for tokens (PKCE [codeVerifier]).
  ///
  /// TODO(verify): app-links deep redirect host must be configured per
  /// platform before this can complete; auth code exchange implemented
  /// but unreachable until redirect is set up.
  Future<Result<SpotifyCredentials>> receiveCredentials({
    required String code,
    required String codeVerifier,
  }) async {
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) {
      return const Result<SpotifyCredentials>.err(
        Failure.permission(message: 'Spotify client id missing'),
      );
    }
    try {
      final response = await _raw.post(
        Uri.parse(_tokenEndpoint),
        headers: <String, String>{
          'user-agent': MetadataHttp.userAgent,
        },
        body: <String, String>{
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'client_id': clientId,
          'code_verifier': codeVerifier,
        },
      );
      if (response.statusCode != 200) {
        return Result<SpotifyCredentials>.err(
          Failure.network(
            message: 'Spotify token HTTP ${response.statusCode}',
          ),
        );
      }
      return _parseToken(response.body);
    } on Object catch (error) {
      return Result<SpotifyCredentials>.err(
        Failure.network(
          message: 'Spotify token exchange failed',
          cause: error,
        ),
      );
    }
  }

  /// Metadata-only public-catalog track search (Bearer [accessToken];
  /// 6 h cache keyed by URL — single-install app, one user per device).
  Future<Result<List<SpotifyTrack>>> searchTrack(
    String q, {
    required String accessToken,
  }) async {
    final url =
        Uri.parse(_searchEndpoint).replace(queryParameters: <String, String>{
      'q': q,
      'type': 'track',
      'limit': '20',
    });
    final response = await _http.getJson(
      url,
      ttl: const Duration(hours: 6),
      extraHeaders: <String, String>{'authorization': 'Bearer $accessToken'},
    );
    return response.fold(
      onErr: (failure) => Result<List<SpotifyTrack>>.err(failure),
      onSuccess: _parseTracks,
    );
  }

  Result<SpotifyCredentials> _parseToken(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['access_token'] is! String) {
        return const Result<SpotifyCredentials>.err(
          Failure.parsing(message: 'Malformed Spotify token response'),
        );
      }
      final expiresIn = decoded['expires_in'];
      final refresh = decoded['refresh_token'];
      return Result<SpotifyCredentials>.success(
        SpotifyCredentials(
          accessToken: decoded['access_token'] as String,
          expiresInSeconds: expiresIn is num ? expiresIn.round() : 3600,
          refreshToken: refresh is String ? refresh : null,
        ),
      );
    } on FormatException catch (error) {
      return Result<SpotifyCredentials>.err(
        Failure.parsing(
          message: 'Malformed Spotify token response',
          cause: error,
        ),
      );
    }
  }

  Result<List<SpotifyTrack>> _parseTracks(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const Result<List<SpotifyTrack>>.err(
          Failure.parsing(message: 'Unexpected Spotify payload'),
        );
      }
      final tracks = decoded['tracks'];
      final items =
          tracks is Map<String, dynamic> ? tracks['items'] : null;
      if (items is! List) {
        return const Result<List<SpotifyTrack>>.success([]);
      }
      final parsed = <SpotifyTrack>[
        for (final item in items)
          if (item is Map<String, dynamic>)
            if (_toTrack(item) case final track?) track,
      ];
      return Result<List<SpotifyTrack>>.success(parsed);
    } on FormatException catch (error) {
      return Result<List<SpotifyTrack>>.err(
        Failure.parsing(
          message: 'Malformed Spotify response',
          cause: error,
        ),
      );
    }
  }

  static SpotifyTrack? _toTrack(Map<String, dynamic> item) {
    final id = item['id'];
    final name = item['name'];
    if (id is! String || name is! String) {
      return null;
    }
    final artists = item['artists'];
    final firstArtist =
        artists is List && artists.isNotEmpty ? artists.first : null;
    final artistName =
        firstArtist is Map<String, dynamic> ? firstArtist['name'] : null;
    final album = item['album'];
    final albumName =
        album is Map<String, dynamic> ? album['name'] : null;
    return SpotifyTrack(
      id: id,
      name: name,
      artistName: artistName is String ? artistName : '',
      albumName: albumName is String ? albumName : null,
    );
  }

  static String _base64UrlNoPad(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
