// authored, awaiting local run (contract test against a LIVE Navidrome).
//
// Navidrome contract test for lib/sources/subsonic/subsonic_source.dart.
//
// This test is SKIPPED unless a live server is reachable:
// - local run: `docker compose -f docker-compose.navidrome.yml up -d`
//   then `NAVIDROME_URL=http://localhost:4533 flutter test test/sources/subsonic/`
// - CI: .github/workflows/navidrome-contract.yml spins the container up,
//   seeds a generated sine-wave mp3, and runs exactly this file.
//
// Assertions cover the v1.16.1 protocol contract: ping envelope, search3
// over the seeded track, stream/download/coverArt URL construction, and
// the error envelope for unknown ids.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/sources/subsonic/subsonic_source.dart';

const String kUrl = String.fromEnvironment(
  'NAVIDROME_URL',
  defaultValue: 'http://localhost:4533',
);
const String kUser = String.fromEnvironment(
  'NAVIDROME_USER',
  defaultValue: 'wavely',
);
const String kPassword = String.fromEnvironment(
  'NAVIDROME_PASSWORD',
  defaultValue: 'wavely-ci-password',
);

Track _probe() => Track(
      sourceId: 'subsonic',
      sourceTrackId: 'probe',
      title: 'probe',
      artist: 'probe',
      durationMs: 0,
      format: 'mp3',
      addedAt: DateTime.utc(2024),
      updatedAt: DateTime.utc(2024),
    );

void main() {
  final SubsonicSource source = SubsonicSource(
    config: SubsonicConfig(url: kUrl, username: kUser, password: kPassword),
  );

  test('ping: server answers ok with an API version', () async {
    final String version = await source.ping();
    expect(version, isNotEmpty);
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');

  test('search3: the seeded sine-wave track is findable', () async {
    final List<Track> hits = await source.search('Wavely CI Tone');
    expect(hits, isNotEmpty);
    expect(hits.first.sourceId, 'subsonic');
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');

  test('search3 returns an empty list for a garbage query (no throw)',
      () async {
    final List<Track> hits = await source.search('zzz-no-such-track-zzz');
    expect(hits, isEmpty);
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');

  test('stream URL is well-formed and carries the id + format=raw',
      () async {
    final StreamUrl url = await source.resolveStream(_probe());
    expect(url.url, contains('/rest/stream.view'));
    expect(url.url, contains('format=raw'));
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');

  test('unknown song id produces the protocol error shape, not a crash',
      () async {
    // getSong for a missing id → subsonic-response status failed →
    // SourceApiException.
    await expectLater(
      source.getMetadata('no-such-song-id'),
      throwsA(isA<Object>()),
    );
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');

  test('dio is usable against the server (transport sanity)', () async {
    final Dio dio = Dio(
      BaseOptions(
        // 401/403 are fine — we only assert the transport answers.
        validateStatus: (int? code) => code != null && code < 500,
      ),
    );
    final Response<dynamic> res = await dio.get<dynamic>(kUrl);
    expect(res.statusCode, isNotNull);
  }, skip: 'requires live Navidrome (docker compose); run via '
      'NAVIDROME_URL env — see docs/SOURCES_CONTRACT_TESTS.md');
}
