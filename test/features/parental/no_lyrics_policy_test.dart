import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/parental/data/no_lyrics_policy.dart';

void main() {
  group('NoLyricsPolicy.parse', () {
    test('parses every stored enum name', () {
      expect(
        NoLyricsPolicy.parse(NoLyricsPolicy.block.name),
        NoLyricsPolicy.block,
      );
      expect(
        NoLyricsPolicy.parse(NoLyricsPolicy.mute.name),
        NoLyricsPolicy.mute,
      );
      expect(
        NoLyricsPolicy.parse(NoLyricsPolicy.allow.name),
        NoLyricsPolicy.allow,
      );
    });

    test('null / empty / unknown values fall back to block (fail-safe)', () {
      // BUG-9 decision: never default to uncensored playback.
      expect(NoLyricsPolicy.parse(null), NoLyricsPolicy.block);
      expect(NoLyricsPolicy.parse(''), NoLyricsPolicy.block);
      expect(NoLyricsPolicy.parse('BLOCK'), NoLyricsPolicy.block);
      expect(NoLyricsPolicy.parse('play_original'), NoLyricsPolicy.block);
    });
  });
}
