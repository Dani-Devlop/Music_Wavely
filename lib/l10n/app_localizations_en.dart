// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Wavely';

  @override
  String get tabHome => 'Home';

  @override
  String get tabLocal => 'Local';

  @override
  String get tabOnline => 'Online';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabSettings => 'Settings';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get next => 'Next';

  @override
  String get previous => 'Previous';

  @override
  String get shuffle => 'Shuffle';

  @override
  String get repeat => 'Repeat';

  @override
  String get repeatOff => 'Repeat off';

  @override
  String get repeatAll => 'Repeat all';

  @override
  String get repeatOne => 'Repeat one';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String get playNext => 'Play next';

  @override
  String get stopAfter => 'Stop after this track';

  @override
  String get openQueue => 'Open queue';

  @override
  String get queue => 'Queue';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get openQueueHint => 'Open queue';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get sleepTimerOff => 'Off';

  @override
  String get sleepTimerEndOfTrack => 'End of track';

  @override
  String sleepTimerIn(String duration) {
    return 'in $duration';
  }

  @override
  String get seekBarLabel => 'Playback progress';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get addBookmark => 'Add bookmark';

  @override
  String get abRepeat => 'A-B repeat';

  @override
  String get speed => 'Speed';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get accentColor => 'Accent color';

  @override
  String get accentPurple => 'Purple';

  @override
  String get accentGreen => 'Green';

  @override
  String get reduceTransparency => 'Reduce transparency';

  @override
  String get reduceTransparencyDesc => 'Disables blur effects';

  @override
  String get amoledBlack => 'AMOLED black';

  @override
  String get amoledBlackDesc => 'Pure black surfaces in dark mode';

  @override
  String get adaptiveAccent => 'Accent from album art';

  @override
  String get adaptiveAccentDesc => 'Tints the theme to the playing cover';

  @override
  String get blurStrength => 'Blur strength';

  @override
  String get blurOff => 'Off';

  @override
  String get cornerRadius => 'Corner radius';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePersian => 'Persian';

  @override
  String get playback => 'Playback';

  @override
  String get equalizerEffects => 'Equalizer & effects';

  @override
  String get equalizerEffectsDesc =>
      'EQ, BassBoost, Reverb, ReplayGain, per-device profiles';

  @override
  String get crossfade => 'Crossfade';

  @override
  String get gaplessPlayback => 'Gapless playback';

  @override
  String get resumeOnStart => 'Resume on start';

  @override
  String get speedSection => 'Playback speed';

  @override
  String get neverPlayLanguages => 'Never play languages';

  @override
  String get library => 'Library';

  @override
  String get folders => 'Folders';

  @override
  String get scanFolders => 'Scan folders';

  @override
  String get storage => 'Storage';

  @override
  String get storageTemplate => 'Storage template';

  @override
  String get blacklist => 'Blacklist';

  @override
  String get whitelist => 'Whitelist';

  @override
  String get rescanLibrary => 'Re-scan library';

  @override
  String get tracks => 'Tracks';

  @override
  String get albums => 'Albums';

  @override
  String get artists => 'Artists';

  @override
  String get genres => 'Genres';

  @override
  String get playlists => 'Playlists';

  @override
  String get playlist => 'Playlist';

  @override
  String get queueTab => 'Queues';

  @override
  String get favorites => 'Favorites';

  @override
  String get recent => 'Recent';

  @override
  String get mostPlayed => 'Most played';

  @override
  String get sort => 'Sort';

  @override
  String get sortByTitle => 'Title';

  @override
  String get sortByArtist => 'Artist';

  @override
  String get sortByAlbum => 'Album';

  @override
  String get sortByDuration => 'Duration';

  @override
  String get sortByAdded => 'Recently added';

  @override
  String get sortByPlays => 'Play count';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get searchLibrary => 'Search library';

  @override
  String get noResults => 'No results';

  @override
  String get selectItems => 'Select items';

  @override
  String get selectAll => 'Select all';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get continueAction => 'Continue';

  @override
  String get retry => 'Retry';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Remove';

  @override
  String get exportAction => 'Export';

  @override
  String get importAction => 'Import';

  @override
  String get tagEditor => 'Tag editor';

  @override
  String tagEditorDesc(int count) {
    return 'Batch-edit metadata for $count tracks';
  }

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldArtist => 'Artist';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldAlbumArtist => 'Album artist';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get fieldYear => 'Year';

  @override
  String get fieldTrackNumber => 'Track number';

  @override
  String get fieldDiscNumber => 'Disc number';

  @override
  String get fieldComment => 'Comment';

  @override
  String get fieldComposer => 'Composer';

  @override
  String get fieldLanguage => 'Language';

  @override
  String get fieldLyrics => 'Lyrics';

  @override
  String get fieldCover => 'Cover art';

  @override
  String get applyChanges => 'Apply changes';

  @override
  String get revertChanges => 'Revert';

  @override
  String get audioCutter => 'Audio cutter';

  @override
  String get setAsRingtone => 'Set as ringtone';

  @override
  String get cutSelection => 'Cut selection';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get lyricsSynced => 'Synced lyrics';

  @override
  String get lyricsPlain => 'Plain lyrics';

  @override
  String get lyricsNone => 'No lyrics found';

  @override
  String get lrcEditor => 'LRC editor';

  @override
  String get stampLine => 'Stamp timestamp';

  @override
  String get shiftLyrics => 'Shift timings';

  @override
  String get tagEditorApplied => 'Tag changes applied';

  @override
  String get ringtoneSet => 'Ringtone updated';

  @override
  String exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String get backupDone => 'Backup completed';

  @override
  String get restoreDone => 'Restore completed';

  @override
  String get onlineTitle => 'Online';

  @override
  String get spotifyStyle => 'Browse';

  @override
  String get news => 'News';

  @override
  String get discovery => 'Discovery';

  @override
  String get charts => 'Charts';

  @override
  String whatsNewTitle(String version) {
    return 'What\'s New in $version';
  }

  @override
  String get updateAvailable => 'Update available';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get upToDate => 'You are up to date';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get privacyFirst => 'Privacy-first, plays only legal sources';

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get errorGeneric => 'Unexpected error';

  @override
  String get errorNetwork => 'Network error — check your connection';

  @override
  String get errorStorage => 'Storage error — check permissions';

  @override
  String get errorPermission => 'Permission denied';

  @override
  String get permissionAudio => 'Audio access';

  @override
  String get permissionAudioDesc => 'Required to scan your music library';

  @override
  String get grantPermission => 'Grant';

  @override
  String get queueMerge => 'Merge queues';

  @override
  String get queueSwitch => 'Switch queue';

  @override
  String get queueSave => 'Save queue';

  @override
  String get queueReorder => 'Reorder';

  @override
  String queueCount(int count) {
    return '$count queues';
  }

  @override
  String get eqPresets => 'Presets';

  @override
  String get eqFlat => 'Flat';

  @override
  String get eqBassBoost => 'Bass boost';

  @override
  String get eqTreble => 'Treble';

  @override
  String get eqVocal => 'Vocal';

  @override
  String get eqRock => 'Rock';

  @override
  String get eqJazz => 'Jazz';

  @override
  String get replayGain => 'ReplayGain';

  @override
  String get replayGainScan => 'Scan loudness';

  @override
  String get replayGainMode => 'ReplayGain mode';

  @override
  String get widgetSmall => 'Wavely small widget';

  @override
  String get widgetControls => 'Wavely playback widget';

  @override
  String get widgetLarge => 'Wavely album widget';

  @override
  String get qsTileLabel => 'Wavely play/pause';
}
