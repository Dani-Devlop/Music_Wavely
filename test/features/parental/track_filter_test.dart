/// Authored, awaiting local run (Task 2-f).
///
/// [TrackFilter] decision matrix with the REAL verdict shape
/// ([TrackVerdict.allowed] / [blocked] / [censorNeeded]): artist/album/
/// genre blocklists win first (case-insensitive), the no-lyrics policy
/// blocks when enabled, blocked words in available lyrics yield
/// censorNeeded (never blocked), and clean lyrics load as-is.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/track_filter.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

BlockedWordRow _word(String word, {int id = 1}) => BlockedWordRow(
      id: id,
      word: word,
      severity: 'moderate',
      language: null,
      addedAt: DateTime(2024, 1, 1),
    );

Track _track({
  String artist = 'Velvet Echo',
  String? album = 'Rivers',
  String? genre = 'Indie Pop',
}) =>
    Track(
      id: 1,
      sourceId: 'local',
      sourceTrackId: 't-1',
      title: 'Neon Rivers',
      artist: artist,
      album: album,
      genre: genre,
      durationMs: 203000,
      format: 'mp3',
      addedAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

const LyricsResult _cleanLyrics = LyricsResult(
  synced: true,
  lines: <LyricLine>[
    LyricLine(startTime: Duration(seconds: 1), text: 'shining bright'),
  ],
);

const LyricsResult _dirtyLyrics = LyricsResult(
  synced: true,
  lines: <LyricLine>[
    LyricLine(startTime: Duration(seconds: 1), text: 'this shit slaps'),
  ],
);

void main() {
  group('TrackFilter.evaluate matrix', () {
    test('clean track with clean lyrics is allowed', () async {
      final filter = TrackFilter(words: [], blockNoLyrics: false);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: [_word('shit')]),
      );
      expect(verdict, TrackVerdict.allowed);
    });

    test('blocked artist wins first — even with dirty lyrics', () async {
      final filter = TrackFilter(
        words: [_word('shit')],
        blockNoLyrics: false,
        blockedArtists: <String>['Evil DJ'],
      );
      final verdict = await filter.evaluate(
        track: _track(artist: 'EVIL DJ'),
        lyrics: _dirtyLyrics,
        matcher: WordMatcher(words: [_word('shit')]),
      );
      expect(verdict, TrackVerdict.blocked);
    });

    test('blocked album blocks (case-insensitive whole value)', () async {
      final filter = TrackFilter(
        words: [],
        blockNoLyrics: false,
        blockedAlbums: <String>['parental advisory album'],
      );
      final verdict = await filter.evaluate(
        track: _track(album: 'Parental Advisory Album'),
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: []),
      );
      expect(verdict, TrackVerdict.blocked);
    });

    test('blocked genre blocks; different genre does not', () async {
      final filter = TrackFilter(
        words: [],
        blockNoLyrics: false,
        blockedGenres: <String>['horrorcore'],
      );
      final blocked = await filter.evaluate(
        track: _track(genre: 'Horrorcore'),
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: []),
      );
      final allowed = await filter.evaluate(
        track: _track(genre: 'Horrorcore Pop'), // whole-value match only
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: []),
      );
      expect(blocked, TrackVerdict.blocked);
      expect(allowed, TrackVerdict.allowed);
    });

    test('no lyrics + no-lyrics policy → blocked', () async {
      final filter = TrackFilter(words: [], blockNoLyrics: true);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: null,
        matcher: WordMatcher(words: []),
      );
      expect(verdict, TrackVerdict.blocked);
    });

    test('no lyrics + policy off → allowed', () async {
      final filter = TrackFilter(words: [], blockNoLyrics: false);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: null,
        matcher: WordMatcher(words: []),
      );
      expect(verdict, TrackVerdict.allowed);
    });

    test('lyrics present but zero lines count as no lyrics', () async {
      const empty = LyricsResult(synced: true, lines: <LyricLine>[]);
      final filter = TrackFilter(words: [], blockNoLyrics: true);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: empty,
        matcher: WordMatcher(words: []),
      );
      expect(verdict, TrackVerdict.blocked);
    });

    test('blocked word inside available lyrics → censorNeeded, not '
        'blocked', () async {
      final filter = TrackFilter(words: [_word('shit')], blockNoLyrics: true);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: _dirtyLyrics,
        matcher: WordMatcher(words: [_word('shit')]),
      );
      expect(verdict, TrackVerdict.censorNeeded);
    });

    test('clean lyrics with a configured word list stay allowed',
        () async {
      final filter = TrackFilter(words: [_word('shit')], blockNoLyrics: false);
      final verdict = await filter.evaluate(
        track: _track(),
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: [_word('shit')]),
      );
      expect(verdict, TrackVerdict.allowed);
    });

    test('metadata blocklists are skipped for null metadata', () async {
      final filter = TrackFilter(
        words: [],
        blockNoLyrics: false,
        blockedArtists: <String>['Evil DJ'],
        blockedAlbums: <String>['X'],
        blockedGenres: <String>['Y'],
      );
      final verdict = await filter.evaluate(
        track: _track(album: null, genre: null),
        lyrics: _cleanLyrics,
        matcher: WordMatcher(words: []),
      );
      expect(verdict, TrackVerdict.allowed);
    });

    test('hasWords mirrors the configured word list', () {
      expect(TrackFilter(words: [], blockNoLyrics: false).hasWords, isFalse);
      expect(
        TrackFilter(words: [_word('shit')], blockNoLyrics: false).hasWords,
        isTrue,
      );
    });
  });
}
