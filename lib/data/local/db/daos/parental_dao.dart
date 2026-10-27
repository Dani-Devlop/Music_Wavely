import 'package:drift/drift.dart';

import 'package:wavely/data/local/db/app_database.dart';
import 'package:wavely/data/local/db/tables/blocked_words.dart';
import 'package:wavely/data/local/db/tables/parental_audit.dart';
import 'package:wavely/data/local/db/tables/profiles_local.dart';

part 'parental_dao.g.dart';

/// Parental-control storage: blocked words, local profiles, audit trail.
@DriftAccessor(tables: [BlockedWords, ProfilesLocal, ParentalAudit])
class ParentalDao extends DatabaseAccessor<AppDatabase>
    with _$ParentalDaoMixin {
  ParentalDao(super.attachedDatabase);

  // -- blocked words --------------------------------------------------------

  Future<List<BlockedWordRow>> allWords() =>
      (select(blockedWords)..orderBy([(w) => OrderingTerm.asc(w.word)])).get();

  Future<int> addWord({
    required String word,
    String severity = 'moderate',
    String? language,
  }) =>
      into(blockedWords).insert(
        BlockedWordsCompanion.insert(
          word: word,
          severity: Value(severity),
          language: Value(language),
          addedAt: DateTime.now(),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  Future<int> removeWord(String word) =>
      (delete(blockedWords)..where((w) => w.word.equals(word))).go();

  // -- profiles -------------------------------------------------------------

  Future<List<LocalProfileRow>> allProfiles() =>
      (select(profilesLocal)..orderBy([(p) => OrderingTerm.asc(p.id)])).get();

  Future<int> createProfile({
    required String name,
    String? pinHash,
    bool blockNoLyrics = false,
  }) =>
      into(profilesLocal).insert(
        LocalProfilesCompanion.insert(
          name: name,
          pinHash: Value(pinHash),
          blockNoLyrics: Value(blockNoLyrics),
          createdAt: DateTime.now(),
        ),
      );

  Future<void> updateProfilePin(int profileId, String? pinHash) =>
      (update(profilesLocal)..where((p) => p.id.equals(profileId)))
          .write(LocalProfilesCompanion(pinHash: Value(pinHash)));

  Future<void> setBlockNoLyrics(int profileId, bool block) =>
      (update(profilesLocal)..where((p) => p.id.equals(profileId)))
          .write(LocalProfilesCompanion(blockNoLyrics: Value(block)));

  // -- audit ----------------------------------------------------------------

  Future<void> audit(String event, {Map<String, Object?> details = const {}}) {
    // Ignore write failures? No — audit is best-effort but local writes to
    // SQLite rarely fail; keep the error surface explicit for callers.
    return into(parentalAudit).insert(
      ParentalAuditCompanion.insert(
        event: event,
        details: Value(details.toString()),
        occurredAt: DateTime.now(),
      ),
    );
  }

  Future<List<ParentalAuditRow>> recentAudit({int limit = 100}) =>
      (select(parentalAudit)
            ..orderBy([(a) => OrderingTerm.desc(a.occurredAt)])
            ..limit(limit))
          .get();
}
