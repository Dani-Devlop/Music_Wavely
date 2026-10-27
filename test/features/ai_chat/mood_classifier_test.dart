/// Authored, awaiting local run (Task 2-f).
///
/// Keyword-scored [MoodClassifier] contract: 20+ free-form sentences mapped
/// to their moods per the real keyword tables, the spec's breakup/
/// heartbreak case (excludedGenres `romantic`/`love`, preferredTags
/// uplifting/empowerment/growth/discipline, languages `en`), tie-break by
/// enum order, case-insensitivity, substring variants and the all-zero →
/// `mood: null` rule. Fully deterministic — no randomness, no I/O.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/ai_chat/data/mood_classifier.dart';

void main() {
  group('MoodClassifier.classify — sentence table', () {
    test('maps 23 sentences to their expected moods', () {
      const cases = <(String, Mood)>[
        // heartbreak keyword families: breakup / heartbroken / cheated /
        // crying over / left me / moved on / devastated / heartbreak.
        ('playlist for getting over a breakup', Mood.heartbreak),
        (
          'she just dumped me, I feel heartbroken and devastated',
          Mood.heartbreak,
        ),
        (
          'my ex cheated on me and I cannot stop crying over us',
          Mood.heartbreak,
        ),
        ('he left me this week and I am so heartbroken', Mood.heartbreak),
        ('I finally moved on after the heartbreak', Mood.heartbreak),
        // uplifting.
        ('I need something uplifting to start the week', Mood.uplifting),
        (
          'motivate me, I want to feel unstoppable at the gym',
          Mood.uplifting,
        ),
        ('pick me up with some inspiring empowerment anthems', Mood.uplifting),
        // focus.
        ('help me focus during a long study session', Mood.focus),
        ('deep work coding playlist, something to concentrate', Mood.focus),
        ('STUDY music for my revision', Mood.focus),
        // party.
        ('banger party tracks for tonight', Mood.party),
        ('turn up the club, we are dancing all night', Mood.party),
        ('hype electronic bangers for a house rave', Mood.party),
        // chill.
        ('chill lo-fi to relax after work', Mood.chill),
        ('mellow and cozy evening unwinding sounds', Mood.chill),
        ('CHILL vibes only', Mood.chill),
        // angry.
        ('I am furious and need to scream something aggressive', Mood.angry),
        ('so angry I could rage at everything', Mood.angry),
        // nostalgic.
        ('throwback songs full of childhood memories', Mood.nostalgic),
        (
          'remember when we listened to the old days classics',
          Mood.nostalgic,
        ),
        // sleep.
        ('dreamy lullabies to help me doze off', Mood.sleep),
        ('cant sleep, need something calm for bedtime', Mood.sleep),
      ];
      expect(cases.length, greaterThanOrEqualTo(20));
      for (final (text, expected) in cases) {
        final result = MoodClassifier.classify(text);
        expect(result.mood, expected, reason: 'text: "$text"');
      }
    });

    test('sentence with zero keyword hits yields a null mood', () {
      expect(
        MoodClassifier.classify('qwerty zxcvbn asdf playlist'),
        const MoodResult(mood: null),
      );
    });
  });

  group('heartbreak spec rule', () {
    test('spec breakup case returns the full heartbreak MoodResult', () {
      // The spec case: the user is heartbroken and explicitly does NOT want
      // romantic / love material; healing energy, English only.
      const result = MoodResult(
        mood: Mood.heartbreak,
        excludedGenres: <String>['romantic', 'love'],
        preferredTags: <String>[
          'uplifting',
          'empowerment',
          'growth',
          'discipline',
        ],
        languages: <String>['en'],
      );
      expect(
        MoodClassifier.classify(
          'she left me and I am devastated — nothing romantic please',
        ),
        result,
      );
      // Same outcome from the plain "breakup" keyword family.
      expect(MoodClassifier.classify('songs for after a breakup'), result);
    });

    test('non-heartbreak moods never carry exclusions or languages', () {
      final result = MoodClassifier.classify('help me focus to study');
      expect(result.mood, Mood.focus);
      expect(result.excludedGenres, isEmpty);
      expect(result.languages, isEmpty);
      expect(
        result.preferredTags,
        <String>['focus', 'instrumental', 'minimal'],
      );
    });
  });

  group('determinism rules', () {
    test('ties resolve to the earliest mood in enum order', () {
      // 'chill' (enum index 4) and 'focus' (index 2) both score 1 → focus.
      expect(
        MoodClassifier.classify('chill and focus mix').mood,
        Mood.focus,
      );
      // 'party' (index 3) and 'heartbreak' (index 0) tie at 1 → heartbreak.
      expect(
        MoodClassifier.classify('party anthems after a heartbreak').mood,
        Mood.heartbreak,
      );
    });

    test('matching is case-insensitive', () {
      expect(MoodClassifier.classify('STUDY AND CODING').mood, Mood.focus);
      expect(MoodClassifier.classify('Party Time').mood, Mood.party);
    });

    test('substring matching hits base keywords via variants', () {
      // 'partying' ⊃ 'party'.
      expect(
        MoodClassifier.classify('partying all night long').mood,
        Mood.party,
      );
      // 'studying' ⊃ 'study'.
      expect(
        MoodClassifier.classify('studying late tonight').mood,
        Mood.focus,
      );
      // 'nostalgic' ⊃ 'nostalg'.
      expect(
        MoodClassifier.classify('a nostalgic summer drive').mood,
        Mood.nostalgic,
      );
      // 'sleepy' ⊃ 'sleep'.
      expect(
        MoodClassifier.classify('a sleepy afternoon mix').mood,
        Mood.sleep,
      );
    });

    test('repeated keywords raise the score for the right mood', () {
      // 'chill' ×2 + 'relax' → chill 3 beats every other mood (0).
      expect(
        MoodClassifier.classify('chill, just chill and relax').mood,
        Mood.chill,
      );
    });
  });
}
