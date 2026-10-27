import 'package:freezed_annotation/freezed_annotation.dart';

part 'lyrics_entities.freezed.dart';

/// A single word inside a synced [LyricLine] (word-level karaoke timing).
@freezed
abstract class LyricWord with _$LyricWord {
  const factory LyricWord({
    required Duration start,
    Duration? end,
    required String text,
  }) = _LyricWord;
}

/// One lyric line, optionally carrying word-level timings.
@freezed
abstract class LyricLine with _$LyricLine {
  const factory LyricLine({
    required Duration startTime,
    Duration? endTime,
    required String text,
    List<LyricWord>? words,
  }) = _LyricLine;
}

/// Result of a lyrics lookup: plain or synced lines plus provider metadata.
@freezed
abstract class LyricsResult with _$LyricsResult {
  const factory LyricsResult({
    required List<LyricLine> lines,
    @Default(<String, String>{}) Map<String, String> metadata,
    @Default(false) bool synced,
  }) = _LyricsResult;
}
