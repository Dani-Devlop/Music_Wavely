import 'package:meta/meta.dart';

/// Listening moods the AI chat can pick up from free-form user text.
enum Mood {
  heartbreak,
  uplifting,
  focus,
  party,
  chill,
  angry,
  nostalgic,
  sleep;

  /// Lowercase display label used on the mood chips row.
  String get label => name;
}

/// Result of scoring free-form text against the mood keyword lists.
///
/// - [mood] is `null` when every keyword score was zero (no signal).
/// - [excludedGenres] carries genres that must NOT be queued for the mood
///   (currently only the heartbreak rule fills this).
/// - [preferredTags] carries tags the queue should lean towards; other moods
///   expose their own keyword tags here.
/// - [languages] restricts queue content to these language codes.
@immutable
class MoodResult {
  const MoodResult({
    required this.mood,
    this.excludedGenres = const <String>[],
    this.preferredTags = const <String>[],
    this.languages = const <String>[],
  });

  final Mood? mood;
  final List<String> excludedGenres;
  final List<String> preferredTags;
  final List<String> languages;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoodResult &&
          other.mood == mood &&
          _listEquals(other.excludedGenres, excludedGenres) &&
          _listEquals(other.preferredTags, preferredTags) &&
          _listEquals(other.languages, languages);

  @override
  int get hashCode => Object.hash(
        mood,
        Object.hashAll(excludedGenres),
        Object.hashAll(preferredTags),
        Object.hashAll(languages),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Spec-mandated heartbreak exclusions: never queue romantic/love material,
/// prefer healing energy, English only.
const List<String> _heartbreakExcludedGenres = <String>['romantic', 'love'];
const List<String> _heartbreakPreferredTags = <String>[
  'uplifting',
  'empowerment',
  'growth',
  'discipline',
];
const List<String> _heartbreakLanguages = <String>['en'];

/// Per-mood keyword dictionaries (>= 6 entries each). Keywords are matched
/// with a case-insensitive substring scan over the lowercased input text, so
/// word variants ("heartbroken", "partying") hit the base keyword.
const Map<Mood, List<String>> _moodKeywords = <Mood, List<String>>{
  Mood.heartbreak: <String>[
    'breakup',
    'break up',
    'heartbroken',
    'heartbreak',
    'left me',
    'cheated',
    'crying over',
    'moved on',
    'devastated',
  ],
  Mood.uplifting: <String>[
    'uplifting',
    'motivat',
    'inspir',
    'empower',
    'unstoppable',
    'pick me up',
    'rise up',
    'energiz',
  ],
  Mood.focus: <String>[
    'focus',
    'study',
    'concentrat',
    'deep work',
    'coding',
    'flow state',
    'productiv',
    'revision',
  ],
  Mood.party: <String>[
    'party',
    'dance',
    'celebrat',
    'club',
    'banger',
    'turn up',
    'hype',
    'rave',
  ],
  Mood.chill: <String>[
    'chill',
    'relax',
    'unwind',
    'laid back',
    'cozy',
    'mellow',
    'lo-fi',
    'easy listening',
  ],
  Mood.angry: <String>[
    'angry',
    'rage',
    'furious',
    'mad at',
    'scream',
    'pissed',
    'aggressiv',
    'steam',
  ],
  Mood.nostalgic: <String>[
    'nostalg',
    'memories',
    'childhood',
    'old days',
    'throwback',
    'remember when',
    'used to listen',
    'school days',
  ],
  Mood.sleep: <String>[
    'sleep',
    'bedtime',
    'lullab',
    'insomnia',
    'drift off',
    'goodnight',
    'dreamy',
    'doze',
  ],
};

/// Tags exposed for non-heartbreak moods (their own keyword family).
const Map<Mood, List<String>> _moodTags = <Mood, List<String>>{
  Mood.uplifting: <String>['uplifting', 'motivation', 'empowerment'],
  Mood.focus: <String>['focus', 'instrumental', 'minimal'],
  Mood.party: <String>['party', 'dance', 'electronic'],
  Mood.chill: <String>['chill', 'acoustic', 'lo-fi'],
  Mood.angry: <String>['angry', 'rock', 'metal'],
  Mood.nostalgic: <String>['nostalgic', 'retro', 'classics'],
  Mood.sleep: <String>['sleep', 'ambient', 'soft'],
};

/// Deterministic keyword-scored mood classifier (no network, no ML).
abstract final class MoodClassifier {
  /// Scores [text] against every mood keyword list.
  ///
  /// - Highest score wins; ties resolve to the mood declared first in the
  ///   [Mood] enum order (deterministic).
  /// - All-zero scores yield a [MoodResult] with `mood == null`.
  /// - Heartbreak additionally applies the spec rule: exclude
  ///   `romantic`/`love` genres, prefer uplifting/empowerment/growth/
  ///   discipline tags, English-only queue content.
  static MoodResult classify(String text) {
    final lower = text.toLowerCase();
    Mood? best;
    var bestScore = 0;
    _moodKeywords.forEach((mood, keywords) {
      var score = 0;
      for (final keyword in keywords) {
        var index = lower.indexOf(keyword);
        while (index != -1) {
          score++;
          index = lower.indexOf(keyword, index + keyword.length);
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = mood;
      }
    });

    final mood = best;
    if (mood == null || bestScore == 0) {
      return const MoodResult(mood: null);
    }
    if (mood == Mood.heartbreak) {
      return const MoodResult(
        mood: Mood.heartbreak,
        excludedGenres: _heartbreakExcludedGenres,
        preferredTags: _heartbreakPreferredTags,
        languages: _heartbreakLanguages,
      );
    }
    return MoodResult(
      mood: mood,
      preferredTags: _moodTags[mood] ?? const <String>[],
    );
  }
}
