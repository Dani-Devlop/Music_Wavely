import 'package:wavely/domain/entities/entities.dart';

/// A lyrics source in the provider chain (embedded tags -> lrclib -> null).
abstract class LyricsProvider {
  String get id;

  Future<LyricsResult?> fetch(Track t);
}
