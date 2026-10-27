/// Authored, awaiting local run.
///
/// No Flutter/Dart SDK exists in the authoring sandbox, so this suite has
/// never been executed. It targets the real `ParentalDao` API in `lib/` and
/// needs `dart run build_runner build` first (generates `app_database.g.dart`
/// and the DAO mixins).
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wavely/data/local/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  group('profiles', () {
    test('createProfile stores name, pin hash and policy flag', () async {
      final profileId = await db.parentalDao.createProfile(
        name: 'Kid',
        pinHash: 'salted-sha256-hex',
        blockNoLyrics: true,
      );

      final row = await (db.select(db.profilesLocal)
            ..where((p) => p.id.equals(profileId)))
          .getSingle();
      expect(row.name, 'Kid');
      expect(row.pinHash, 'salted-sha256-hex');
      expect(row.blockNoLyrics, isTrue);
      expect(row.createdAt, isNotNull);
    });

    test('a profile without a pin defaults to blockNoLyrics=false', () async {
      final profileId = await db.parentalDao.createProfile(name: 'Open');

      final row = await (db.select(db.profilesLocal)
            ..where((p) => p.id.equals(profileId)))
          .getSingle();
      expect(row.pinHash, isNull);
      expect(row.blockNoLyrics, isFalse);
    });

    test('allProfiles returns rows ordered by id', () async {
      await db.parentalDao.createProfile(name: 'First');
      await db.parentalDao.createProfile(name: 'Second');

      final profiles = await db.parentalDao.allProfiles();

      expect(profiles.map((p) => p.name), ['First', 'Second']);
    });

    test('updateProfilePin sets and clears the hash', () async {
      final profileId = await db.parentalDao.createProfile(name: 'Kid');

      await db.parentalDao.updateProfilePin(profileId, 'new-hash');
      var row = await db.select(db.profilesLocal).getSingle();
      expect(row.pinHash, 'new-hash');

      await db.parentalDao.updateProfilePin(profileId, null);
      row = await db.select(db.profilesLocal).getSingle();
      expect(row.pinHash, isNull);
    });

    test('setBlockNoLyrics toggles the policy flag', () async {
      final profileId = await db.parentalDao.createProfile(name: 'Kid');

      await db.parentalDao.setBlockNoLyrics(profileId, true);
      var row = await db.select(db.profilesLocal).getSingle();
      expect(row.blockNoLyrics, isTrue);

      await db.parentalDao.setBlockNoLyrics(profileId, false);
      row = await db.select(db.profilesLocal).getSingle();
      expect(row.blockNoLyrics, isFalse);
    });
  });

  group('blocked words', () {
    test('addWord stores defaults and custom severity/language', () async {
      final id1 = await db.parentalDao.addWord(word: 'heck');
      final id2 = await db.parentalDao.addWord(
        word: 'swore',
        severity: 'severe',
        language: 'en',
      );

      final words = await db.parentalDao.allWords();
      expect(words, hasLength(2));
      expect(words[0].word, 'heck');
      expect(words[0].severity, 'moderate', reason: 'column default');
      expect(words[0].language, isNull);
      expect(words[1].id, isNot(id1));
      expect(words[1].id, id2);
      expect(words[1].severity, 'severe');
      expect(words[1].language, 'en');
      expect(words.every((w) => w.addedAt != null), isTrue);
    });

    test('allWords is sorted by word ascending', () async {
      await db.parentalDao.addWord(word: 'zeta');
      await db.parentalDao.addWord(word: 'alpha');
      await db.parentalDao.addWord(word: 'mid');

      final words = await db.parentalDao.allWords();

      expect(words.map((w) => w.word), ['alpha', 'mid', 'zeta']);
    });

    test('adding the same word twice is ignored (unique word)', () async {
      await db.parentalDao.addWord(word: 'dupe');
      await db.parentalDao.addWord(word: 'dupe', severity: 'severe');

      final words = await db.parentalDao.allWords();
      expect(words, hasLength(1));
      expect(words.single.severity, 'moderate',
          reason: 'first insert wins, the retry is ignored');
    });

    test('removeWord deletes the row and reports the affected count',
        () async {
      await db.parentalDao.addWord(word: 'gone');
      await db.parentalDao.addWord(word: 'stays');

      expect(await db.parentalDao.removeWord('gone'), 1);
      expect(await db.parentalDao.removeWord('gone'), 0);

      final words = await db.parentalDao.allWords();
      expect(words.map((w) => w.word), ['stays']);
    });
  });

  group('audit trail', () {
    test('audit appends an event with default or custom details', () async {
      await db.parentalDao.audit('pin_set');
      await db.parentalDao.audit(
        'track_censored',
        details: const {'trackId': 12, 'word': 'heck'},
      );

      final rows = await db.parentalDao.recentAudit();
      expect(rows, hasLength(2));
      expect(rows[0].event, 'track_censored');
      expect(rows[0].details, contains('trackId'),
          reason: 'details are stored as a stringified map');
      expect(rows[0].occurredAt, isNotNull);
      expect(rows[1].event, 'pin_set');
      expect(rows[1].details, '{}', reason: 'default details');
    });

    test('recentAudit returns newest first', () async {
      // Direct inserts with explicit timestamps keep the ordering test
      // deterministic (the DAO stamps `now` on real writes).
      await db.into(db.parentalAudit).insert(
            ParentalAuditCompanion.insert(
              event: 'old',
              occurredAt: DateTime(2024, 1, 1),
            ),
          );
      await db.into(db.parentalAudit).insert(
            ParentalAuditCompanion.insert(
              event: 'new',
              occurredAt: DateTime(2024, 1, 2),
            ),
          );

      final rows = await db.parentalDao.recentAudit();

      expect(rows.map((r) => r.event), ['new', 'old']);
    });

    test('recentAudit honors the limit', () async {
      for (var i = 0; i < 5; i++) {
        await db.into(db.parentalAudit).insert(
              ParentalAuditCompanion.insert(
                event: 'e$i',
                occurredAt: DateTime(2024, 1, 1).add(Duration(days: i)),
              ),
            );
      }

      final rows = await db.parentalDao.recentAudit(limit: 2);

      expect(rows.map((r) => r.event), ['e4', 'e3']);
    });
  });
}
