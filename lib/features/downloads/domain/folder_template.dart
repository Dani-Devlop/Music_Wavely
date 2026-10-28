import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/downloads/domain/filename_sanitizer.dart';

/// Resolved artist geography for the folder template.
class ArtistGeo {
  /// Creates the geo pair.
  const ArtistGeo({this.continent = 'Unknown', this.country = 'Unknown'});

  /// Continent name (capitalised, e.g. `Europe`), `Unknown` when unresolvable.
  final String continent;

  /// Country/area name (e.g. `United Kingdom`), `Unknown` when unresolvable.
  final String country;
}

/// Resolves artist → [ArtistGeo] via the Stage 1.2 MusicBrainz client.
///
/// MusicBrainz' artist search returns the artist's origin/birth `area`
/// name; the resolver maps that area to a continent with a static lookup
/// of common areas and falls back to `Unknown` on any miss or failure
/// (documented: area is a free-form name, not an ISO code).
class ArtistGeoResolver {
  /// Creates the resolver over a [lookup] function (the MusicBrainz client
  /// call in production, a fake in tests).
  ArtistGeoResolver({required Future<String?> Function(String artist) lookup})
      : _lookup = lookup;

  final Future<String?> Function(String artist) _lookup;

  final Map<String, ArtistGeo> _cache = <String, ArtistGeo>{};

  /// Resolves [artist]; never throws. Blank artists resolve to Unknown.
  Future<ArtistGeo> resolve(String artist) async {
    final String key = artist.trim().toLowerCase();
    if (key.isEmpty) {
      return const ArtistGeo();
    }
    final ArtistGeo? cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    String? area;
    try {
      area = await _lookup(artist);
    } on Object {
      area = null;
    }
    final ArtistGeo geo = ArtistGeo(
      continent: continentForArea(area),
      country: (area == null || area.trim().isEmpty) ? 'Unknown' : area.trim(),
    );
    _cache[key] = geo;
    return geo;
  }

  /// Static area-name → continent map (common MusicBrainz areas; anything
  /// else maps to `Unknown`).
  static String continentForArea(String? area) {
    if (area == null) {
      return 'Unknown';
    }
    switch (area.trim().toLowerCase()) {
      // Europe
      case 'united kingdom':
      case 'ireland':
      case 'france':
      case 'germany':
      case 'netherlands':
      case 'belgium':
      case 'spain':
      case 'portugal':
      case 'italy':
      case 'austria':
      case 'switzerland':
      case 'sweden':
      case 'norway':
      case 'denmark':
      case 'finland':
      case 'iceland':
      case 'poland':
      case 'czechia':
      case 'hungary':
      case 'romania':
      case 'greece':
      case 'russia':
        return 'Europe';
      // North America
      case 'united states':
      case 'united states of america':
      case 'canada':
      case 'mexico':
        return 'North America';
      // South America
      case 'brazil':
      case 'argentina':
      case 'chile':
      case 'colombia':
      case 'peru':
      case 'uruguay':
        return 'South America';
      // Asia
      case 'japan':
      case 'south korea':
      case 'china':
      case 'india':
      case 'indonesia':
      case 'philippines':
      case 'thailand':
      case 'vietnam':
      case 'israel':
      case 'turkey':
      case 'iran':
      case 'lebanon':
        return 'Asia';
      // Africa
      case 'south africa':
      case 'nigeria':
      case 'egypt':
      case 'kenya':
      case 'ghana':
      case 'morocco':
      case 'algeria':
      case 'ethiopia':
        return 'Africa';
      // Oceania
      case 'australia':
      case 'new zealand':
        return 'Oceania';
      default:
        return 'Unknown';
    }
  }
}

/// Renders the user-configurable download folder template.
///
/// Placeholders: `{continent}`, `{country}`, `{genre}`, `{artist}`,
/// `{album}`, `{year}`, `{title}`, `{trackNumber}`. Every rendered segment
/// runs through the filename sanitizer. Default template:
/// `Music/{continent}/{country}/{genre}`.
class FolderTemplate {
  /// Creates a template renderer; [geoResolver] injectable for tests.
  FolderTemplate({
    this.template = FolderTemplate.defaultTemplate,
    ArtistGeoResolver? geoResolver,
  }) : _geoResolver = geoResolver;

  /// Default template per Stage 2.1 spec.
  static const String defaultTemplate =
      'Music/{continent}/{country}/{genre}';

  /// The raw template string.
  final String template;

  final ArtistGeoResolver? _geoResolver;

  /// Renders the directory path for [track] under [baseDir].
  ///
  /// Values missing from metadata fall back to `Unknown`; blank segments
  /// are dropped so paths never contain `//`. The file name itself is
  /// appended by the caller via [buildTrackFilename].
  Future<String> renderFor(
    Track track, {
    required String baseDir,
  }) async {
    ArtistGeo geo = const ArtistGeo();
    final ArtistGeoResolver? resolver = _geoResolver;
    if (resolver != null) {
      geo = await resolver.resolve(track.artist);
    }
    final String year = track.addedAt.year.toString();
    final String trackNumber = '00';
    final Map<String, String> values = <String, String>{
      'continent': geo.continent,
      'country': geo.country,
      'genre': track.genre ?? 'Unknown',
      'artist': track.artistOrUnknown,
      'album': track.album ?? 'Unknown',
      'year': year,
      'title': track.title,
      'trackNumber': trackNumber,
    };
    var rendered = template;
    values.forEach((String k, String v) {
      rendered = rendered.replaceAll('{$k}', v);
    });
    final List<String> segments = <String>[
      for (final String seg in rendered.split('/'))
        if (seg.trim().isNotEmpty) sanitizeFilename(seg.trim()),
    ];
    return '$baseDir/${segments.join('/')}';
  }
}
