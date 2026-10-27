import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/data/local/db/app_database.dart';

/// App-wide [AppDatabase] singleton; closed when the provider container
/// disposes. Tests override this with a memory-backed database.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
