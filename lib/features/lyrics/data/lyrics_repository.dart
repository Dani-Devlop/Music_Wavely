import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/domain/repositories/lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/embedded_lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lrclib_lyrics_provider.dart';
import 'package:wavely/features/lyrics/data/lyrics_cache.dart';
import 'package:wavely/features/lyrics/domain/lrc_parser.dart';

/// Ordered provider chain with a cache-first read strategy.
///
/// 1. A cached row (any provider) short-circuits everything — cached
///    results are kept forever per Stage 1.1.
/// 2. Otherwise providers are consulted in order; the first non-null
///    result wins. Providers that fetch from the network (LRCLIB) cache
///    their own raw payload; if the winning provider did not populate the
///    cache (e.g. an in-memory provider), the repository writes a
///    best-effort re-serialization of the parsed result so the next fetch
///    short-circuits.
/// 3. All providers failing -> null (misses are NOT cached).
class LyricsRepository {
  LyricsRepository({
    required List<LyricsProvider> providers,
    required LyricsCache cache,
  })  : _providers = List<LyricsProvider>.unmodifiable(providers),
        _cache = cache;

  final List<LyricsProvider> _providers;
  final LyricsCache _cache;

  Future<LyricsResult?> fetch(Track t) async {
    final trackId = t.id;
    if (trackId == null) {
      return null;
    }
    final row = await _cache.get(trackId: trackId);
    if (row != null) {
      return _parseRow(row);
    }
    for (final provider in _providers) {
      // A provider failure (network down, parser bug, ...) must not break
      // the chain — degrade to the next provider instead (per the
      // Stage 1.1 "provider failure resilience" contract).
      LyricsResult? result;
      try {
        result = await provider.fetch(t);
      } on Object catch (_) {
        continue;
      }
      if (result == null || result.lines.isEmpty) {
        continue;
      }
      final existing = await _cache.get(trackId: trackId);
      if (existing == null) {
        try {
          await _cache.upsert(
            trackId: trackId,
            provider: provider.id,
            syncedLrc: result.synced ? _serializeSynced(result) : null,
            plainText: result.synced ? null : _serializePlain(result),
          );
        } on Object catch (_) {
          // Cache write failures must not break lyric delivery.
        }
      }
      return result;
    }
    return null;
  }

  LyricsResult? _parseRow(CachedLyrics row) {
    if (row.hasSynced) {
      return LrcParser.parse(row.syncedLrc!);
    }
    final plain = row.plainText;
    if (plain == null || plain.trim().isEmpty) {
      return null;
    }
    return LrcParser.parse(plain);
  }

  String _serializeSynced(LyricsResult result) => <String>[
        for (final line in result.lines)
          '[${_stamp(line.startTime)}]${line.text}',
      ].join('\n');

  String _serializePlain(LyricsResult result) =>
      result.lines.map((line) => line.text).join('\n');

  String _stamp(Duration d) {
    final ms = d.inMilliseconds;
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final hundredths = ((ms % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds.$hundredths';
  }
}

/// Repository binding. [lyricsCacheProvider] defaults to a no-op cache and
/// is overridden by the composition root (Task 4) with the Drift-backed
/// implementation.
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final cache = ref.watch(lyricsCacheProvider);
  return LyricsRepository(
    providers: <LyricsProvider>[
      EmbeddedLyricsProvider(cache: cache),
      LrclibLyricsProvider(
        dio: Dio(BaseOptions(baseUrl: LrclibLyricsProvider.baseUrl)),
        cache: cache,
      ),
    ],
    cache: cache,
  );
});
