import 'package:drift/drift.dart';

/// One blocked word of the parental word filter (Stage 1.2, B8).
@DataClassName('BlockedWordRow', companion: 'BlockedWordsCompanion')
class BlockedWords extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The word as entered by the parent (lowercased by [WordMatcher] input
  /// preparation, stored verbatim here).
  TextColumn get word => text().unique();

  /// `mild` | `moderate` | `severe` — drives the censor beep vs mute choice.
  TextColumn get severity => text().withDefault(const Constant('moderate'))();

  /// Optional ISO language tag; null matches any language.
  TextColumn get language => text().nullable()();

  DateTimeColumn get addedAt => dateTime()();
}
