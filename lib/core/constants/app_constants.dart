/// Application-wide constants for Wavely.
///
/// Every magic number used across the app must live here (visual tokens live
/// in `lib/design_system/tokens/` instead).
abstract final class AppConstants {
  /// Timings in milliseconds, unless the name says otherwise.
  static const int animationMs = 300;
  static const int fastAnimationMs = 150;
  static const int searchDebounceMs = 300;
  static const int scrollPageSize = 200;
  static const int scanDebounceSeconds = 2;
  static const int scanErrorLogLimit = 100;
  static const int retryCount = 3;
  static const int retryBackoffMs = 500;
  static const int lyricsAutoScrollResumeDelaySeconds = 3;
  static const int crossfadeMaxSeconds = 12;

  /// Rendering / performance budgets.
  static const int maxBackdropFiltersPerScreen = 3;
  static const double blurSigmaSurface = 24;
  static const double blurSigmaElevated = 32;

  /// Lyrics view tuning.
  static const double lyricsCurrentLineScale = 1.05;
  static const double lyricsNeighborOpacity = 0.4;

  /// Layout metrics.
  static const double nowPlayingCoverSizeMobile = 300;
  static const double nowPlayingCoverSizeDesktop = 400;
  static const double touchTargetMin = 44;
  static const double trackTileCoverSize = 40;

  /// Playback behaviour.
  static const List<int> sleepTimerPresetsMinutes = <int>[
    5,
    10,
    15,
    30,
    45,
    60,
    90,
  ];
  static const int shuffleNoRepeatWindow = 10;

  /// Persistence keys.
  static const String queuePersistKey = 'wavely.queue.v1';
  static const String queueIndexPersistKey = 'wavely.queue.index.v1';
  static const String queuePositionPersistKey = 'wavely.queue.position.ms.v1';

  // Stage 3 audit (BUG-11): shuffle/repeat mode and the pre-shuffle order are
  // persisted so the true album order survives restarts while shuffled.
  static const String queueShufflePersistKey = 'wavely.queue.shuffle.v1';
  static const String queueRepeatPersistKey = 'wavely.queue.repeat.v1';
  static const String queueOriginalPersistKey = 'wavely.queue.original.v1';
  static const String settingsKeyPrefix = 'wavely.settings.';

  /// Filesystem layout.
  static const String coversDirName = 'covers';

  /// Full-text search page size.
  static const int ftsPageSize = 50;
}
