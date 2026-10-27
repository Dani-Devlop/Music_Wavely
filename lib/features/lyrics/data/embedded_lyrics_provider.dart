import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/lyrics/domain/lrc_parser.dart';

/// Serves lyrics that were embedded into the file during the library scan
/// (stored in the lyrics cache table).
///
/// This provider only READS the cache; embedded rows are written by the
/// scanner (Task on library ingestion), never fetched from the network.
class EmbeddedLyricsProvider implements LyricsProvider {
  const EmbeddedLyricsProvider({required LyricsCache cache})
      : _cache = cache;

  static const String providerId = 'embedded';

  final LyricsCache _cache;

  @override
  String get id => providerId;

  @override
  Future<LyricsResult?> fetch(Track t) async {
    final trackId = t.id;
    if (trackId == null) {
      return null;
    }
    final row = await _cache.get(trackId: trackId);
    if (row == null) {
      return null;
    }
    if (row.hasSynced) {
      return LrcParser.parse(row.syncedLrc!);
    }
    final plain = row.plainText;
    if (plain == null || plain.trim().isEmpty) {
      return null;
    }
    return LrcParser.parse(plain);
  }
}
