/// Authored, awaiting local run (Task 2-f).
///
/// [CensorPlanner] contract: line-level mute windows from synced lyrics +
/// blocked words, adjacency merging, the "no synced lyrics" no-plan result,
/// the empty-blocked-words empty plan and overlapping words in one line
/// producing a single range.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/domain/entities/entities.dart';
import 'package:wavely/features/parental/data/censor_planner.dart';
import 'package:wavely/features/parental/data/word_matcher.dart';

WordMatcher _matcher(List<String> words) => WordMatcher(
      words: <BlockedWordRow>[
        for (var i = 0; i < words.length; i++)
          BlockedWordRow(
            id: i + 1,
            word: words[i],
            severity: 'moderate',
            language: null,
            addedAt: DateTime(2024, 1, 1),
          ),
      ],
    );

LyricLine _line(int ms, String text) => LyricLine(
      startTime: Duration(milliseconds: ms),
      text: text,
    );

void main() {
  test('plans (startMs, endMs) ranges from synced lyrics; last line uses '
      'the 4s tail', () {
    final lyrics = LyricsResult(
      synced: true,
      lines: <LyricLine>[
        _line(1000, 'nothing bad here'),
        _line(2000, 'this shit is loud'),
        _line(3500, 'clean again'),
        _line(5000, 'one final damn line'),
      ],
    );
    final plan = CensorPlanner.plan(
      lyrics: lyrics,
      matcher: _matcher(<String>['shit', 'damn']),
    );
    expect(plan.hasPlan, isTrue);
    expect(plan.reason, isNull);
    // Line 1 is muted until line 2 starts; line 3 is the last → +4000ms.
    expect(plan.ranges, <CensorRange>[(2000, 3500), (5000, 9000)]);
    expect(CensorPlanner.lineTailMs, 4000);
    expect(plan.isEmpty, isFalse);
  });

  test('adjacent matched lines merge into one window', () {
    final lyrics = LyricsResult(
      synced: true,
      lines: <LyricLine>[
        _line(0, 'damn intro'),
        _line(1000, 'more shit here'),
        _line(2000, 'even hell breaks loose'),
        _line(3000, 'finally clean'),
      ],
    );
    final plan = CensorPlanner.plan(
      lyrics: lyrics,
      matcher: _matcher(<String>['damn', 'shit', 'hell']),
    );
    // Three back-to-back windows (0,1000)(1000,2000)(2000,3000) collapse.
    expect(plan.ranges, <CensorRange>[(0, 3000)]);
  });

  test('no synced timestamps → no plan at all', () {
    const unsynced = LyricsResult(
      synced: false,
      lines: <LyricLine>[
        LyricLine(startTime: Duration.zero, text: 'total shit'),
      ],
    );
    final fromUnsynced = CensorPlanner.plan(
      lyrics: unsynced,
      matcher: _matcher(<String>['shit']),
    );
    expect(fromUnsynced.hasPlan, isFalse);
    expect(fromUnsynced.reason, 'no synced lyrics');
    expect(fromUnsynced.ranges, isEmpty);

    // No lyrics at all is the same story.
    final fromNull = CensorPlanner.plan(
      lyrics: null,
      matcher: _matcher(<String>['shit']),
    );
    expect(fromNull.hasPlan, isFalse);
    expect(fromNull.reason, 'no synced lyrics');
  });

  test('empty blocked-word list → a valid but empty plan', () {
    final lyrics = LyricsResult(
      synced: true,
      lines: <LyricLine>[
        _line(0, 'pristine lyrics'),
        _line(1500, 'still clean'),
      ],
    );
    final plan = CensorPlanner.plan(
      lyrics: lyrics,
      matcher: _matcher(<String>[]),
    );
    expect(plan.hasPlan, isTrue); // sync data was usable…
    expect(plan.ranges, isEmpty); // …but there is nothing to mute
    expect(plan.reason, isNull);
    expect(plan.isEmpty, isTrue);
  });

  test('overlapping words on one line produce a single range', () {
    final lyrics = LyricsResult(
      synced: true,
      lines: <LyricLine>[
        _line(0, 'clean opener'),
        _line(1000, 'damn it all'),
        _line(2500, 'clean closer'),
      ],
    );
    // 'damn' and 'damn it' both hit the same line; the matcher's
    // non-overlapping result plus the line-level policy must yield
    // exactly one window (never one per word).
    final plan = CensorPlanner.plan(
      lyrics: lyrics,
      matcher: _matcher(<String>['damn', 'damn it']),
    );
    expect(plan.ranges, <CensorRange>[(1000, 2500)]);
  });
}
