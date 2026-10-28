// authored, awaiting local run.
//
// Unit tests for lib/features/downloads/domain/folder_template.dart —
// 10 cases covering every placeholder, Unknown fallbacks, continent
// mapping, sanitisation of rendered segments, blank-segment dropping and
// the default template.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/downloads/domain/folder_template.dart';

Track _track({
  String title = 'Aurora',
  String artist = 'Nova',
  String? album,
  String? genre,
  DateTime? addedAt,
  String format = 'mp3',
}) {
  final DateTime at = addedAt ?? DateTime.utc(2024, 5, 17);
  return Track(
    sourceId: 'jamendo',
    sourceTrackId: 'tr-1',
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    durationMs: 1000,
    format: format,
    addedAt: at,
    updatedAt: at,
  );
}

ArtistGeoResolver _geo(String? area) => ArtistGeoResolver(
      lookup: (String artist) async => area,
    );

Future<String> render(
  String template, {
  required Track track,
  ArtistGeoResolver? geo,
  String baseDir = '/base',
}) {
  final FolderTemplate t = FolderTemplate(
    template: template,
    geoResolver: geo,
  );
  return t.renderFor(track, baseDir: baseDir);
}

void main() {
  group('FolderTemplate.renderFor (10 cases)', () {
    test('1. default template renders continent/country/genre', () async {
      final String path = await render(
        FolderTemplate.defaultTemplate,
        track: _track(genre: 'Ambient'),
        geo: _geo('Germany'),
      );
      expect(path, '/base/Music/Europe/Germany/Ambient');
    });

    test('2. unresolvable geography falls back to Unknown', () async {
      final String path = await render(
        FolderTemplate.defaultTemplate,
        track: _track(genre: 'Ambient'),
        geo: _geo(null),
      );
      expect(path, '/base/Music/Unknown/Unknown/Ambient');
    });

    test('3. missing genre falls back to Unknown', () async {
      final String path = await render(
        FolderTemplate.defaultTemplate,
        track: _track(genre: null),
        geo: _geo('Japan'),
      );
      expect(path, '/base/Music/Asia/Japan/Unknown');
    });

    test('4. blank artist renders Unknown Artist', () async {
      final String path = await render(
        'Music/{artist}',
        track: _track(artist: ''),
      );
      expect(path, '/base/Music/Unknown Artist');
    });

    test('5. {album} and {title} placeholders render', () async {
      final String path = await render(
        '{artist}/{album}/{title}',
        track: _track(album: 'North'),
      );
      expect(path, '/base/Nova/North/Aurora');
    });

    test('6. {year} comes from addedAt', () async {
      final String path = await render(
        '{year}/{title}',
        track: _track(addedAt: DateTime.utc(2023, 1, 1)),
      );
      expect(path, '/base/2023/Aurora');
    });

    test('7. {trackNumber} placeholder renders (Stage 2.1 constant 00)',
        () async {
      final String path = await render(
        '{trackNumber} - {title}',
        track: _track(),
      );
      expect(path, '/base/00 - Aurora');
    });

    test('8. rendered segments are sanitized (illegal chars)', () async {
      final String path = await render(
        '{artist}/{title}',
        track: _track(title: 'a<b>?c'),
      );
      expect(path, '/base/Nova/a_b__c');
    });

    test('9. blank segments are dropped (no double slashes)', () async {
      // Unknown values are never blank, so blank-drop is exercised via a
      // template with empty segments.
      final String path = await render(
        'Music//{title}',
        track: _track(),
      );
      expect(path, '/base/Music/Aurora');
    });

    test('10. continent map covers common areas and unknowns', () {
      expect(
        ArtistGeoResolver.continentForArea('united kingdom'),
        'Europe',
      );
      expect(
        ArtistGeoResolver.continentForArea('United States'),
        'North America',
      );
      expect(
        ArtistGeoResolver.continentForArea('brazil'),
        'South America',
      );
      expect(ArtistGeoResolver.continentForArea('japan'), 'Asia');
      expect(ArtistGeoResolver.continentForArea('kenya'), 'Africa');
      expect(ArtistGeoResolver.continentForArea('australia'), 'Oceania');
      expect(ArtistGeoResolver.continentForArea('Atlantis'), 'Unknown');
      expect(ArtistGeoResolver.continentForArea(null), 'Unknown');
    });

    test('resolver failure (throwing lookup) still yields Unknown', () async {
      final FolderTemplate t = FolderTemplate(
        template: FolderTemplate.defaultTemplate,
        geoResolver: ArtistGeoResolver(
          lookup: (String artist) async => throw StateError('MB down'),
        ),
      );
      final String path = await t.renderFor(
        _track(genre: 'Ambient'),
        baseDir: '/base',
      );
      expect(path, '/base/Music/Unknown/Unknown/Ambient');
    });

    test('resolver results are cached per artist', () async {
      var calls = 0;
      final ArtistGeoResolver geo = ArtistGeoResolver(
        lookup: (String artist) async {
          calls++;
          return 'Norway';
        },
      );
      final FolderTemplate t = FolderTemplate(
        template: FolderTemplate.defaultTemplate,
        geoResolver: geo,
      );
      await t.renderFor(_track(), baseDir: '/base');
      await t.renderFor(_track(), baseDir: '/base');
      expect(calls, 1);
    });
  });

  group('ArtistGeo', () {
    test('defaults are Unknown', () {
      const ArtistGeo g = ArtistGeo();
      expect(g.continent, 'Unknown');
      expect(g.country, 'Unknown');
    });
  });
}
