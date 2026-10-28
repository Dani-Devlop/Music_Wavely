import 'package:drift/drift.dart';

/// Local child profile for parental control (Stage 1.2, B8).
///
/// Remote counterpart lives in Supabase `profiles`; this table mirrors the
/// pieces parental control needs offline (name, PIN hash, policy flags).
@DataClassName('LocalProfileRow', companion: 'LocalProfilesCompanion')
class ProfilesLocal extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  /// salted sha256 of the 4-8 digit PIN, hex-encoded.
  TextColumn get pinHash => text().nullable()();

  /// When true, tracks without ANY lyrics source are blocked entirely.
  BoolColumn get blockNoLyrics => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
}
