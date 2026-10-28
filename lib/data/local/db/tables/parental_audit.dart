import 'package:drift/drift.dart';

/// Append-only audit trail of parental-control events (Stage 1.2, B8).
@DataClassName('ParentalAuditRow', companion: 'ParentalAuditCompanion')
@TableIndex(name: 'idx_parental_audit_at', columns: {#occurredAt})
class ParentalAudit extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// What happened: `pin_set` | `pin_changed` | `word_added` | `word_removed`
  /// | `track_blocked` | `track_censored` | `profile_created` | ...
  TextColumn get event => text()();

  /// Free-form details (JSON), e.g. `{"trackId": 12, "word": "x"}`.
  TextColumn get details => text().withDefault(const Constant('{}'))();

  DateTimeColumn get occurredAt => dateTime()();
}
