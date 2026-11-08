import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// App display name
  ///
  /// In en, this message translates to:
  /// **'Wavely'**
  String get appName;

  /// Bottom navigation tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get tabLocal;

  /// No description provided for @tabOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get tabOnline;

  /// No description provided for @tabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat off'**
  String get repeatOff;

  /// No description provided for @repeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat all'**
  String get repeatAll;

  /// No description provided for @repeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat one'**
  String get repeatOne;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @stopAfter.
  ///
  /// In en, this message translates to:
  /// **'Stop after this track'**
  String get stopAfter;

  /// No description provided for @openQueue.
  ///
  /// In en, this message translates to:
  /// **'Open queue'**
  String get openQueue;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlaying;

  /// No description provided for @openQueueHint.
  ///
  /// In en, this message translates to:
  /// **'Open queue'**
  String get openQueueHint;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @sleepTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get sleepTimerOff;

  /// No description provided for @sleepTimerEndOfTrack.
  ///
  /// In en, this message translates to:
  /// **'End of track'**
  String get sleepTimerEndOfTrack;

  /// No description provided for @sleepTimerIn.
  ///
  /// In en, this message translates to:
  /// **'in {duration}'**
  String sleepTimerIn(String duration);

  /// No description provided for @seekBarLabel.
  ///
  /// In en, this message translates to:
  /// **'Playback progress'**
  String get seekBarLabel;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add bookmark'**
  String get addBookmark;

  /// No description provided for @abRepeat.
  ///
  /// In en, this message translates to:
  /// **'A-B repeat'**
  String get abRepeat;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @accentPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get accentPurple;

  /// No description provided for @accentGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get accentGreen;

  /// No description provided for @reduceTransparency.
  ///
  /// In en, this message translates to:
  /// **'Reduce transparency'**
  String get reduceTransparency;

  /// No description provided for @reduceTransparencyDesc.
  ///
  /// In en, this message translates to:
  /// **'Disables blur effects'**
  String get reduceTransparencyDesc;

  /// No description provided for @amoledBlack.
  ///
  /// In en, this message translates to:
  /// **'AMOLED black'**
  String get amoledBlack;

  /// No description provided for @amoledBlackDesc.
  ///
  /// In en, this message translates to:
  /// **'Pure black surfaces in dark mode'**
  String get amoledBlackDesc;

  /// No description provided for @adaptiveAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent from album art'**
  String get adaptiveAccent;

  /// No description provided for @adaptiveAccentDesc.
  ///
  /// In en, this message translates to:
  /// **'Tints the theme to the playing cover'**
  String get adaptiveAccentDesc;

  /// No description provided for @blurStrength.
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get blurStrength;

  /// No description provided for @blurOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get blurOff;

  /// No description provided for @cornerRadius.
  ///
  /// In en, this message translates to:
  /// **'Corner radius'**
  String get cornerRadius;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get languagePersian;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// No description provided for @equalizerEffects.
  ///
  /// In en, this message translates to:
  /// **'Equalizer & effects'**
  String get equalizerEffects;

  /// No description provided for @equalizerEffectsDesc.
  ///
  /// In en, this message translates to:
  /// **'EQ, BassBoost, Reverb, ReplayGain, per-device profiles'**
  String get equalizerEffectsDesc;

  /// No description provided for @crossfade.
  ///
  /// In en, this message translates to:
  /// **'Crossfade'**
  String get crossfade;

  /// No description provided for @gaplessPlayback.
  ///
  /// In en, this message translates to:
  /// **'Gapless playback'**
  String get gaplessPlayback;

  /// No description provided for @resumeOnStart.
  ///
  /// In en, this message translates to:
  /// **'Resume on start'**
  String get resumeOnStart;

  /// No description provided for @speedSection.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get speedSection;

  /// No description provided for @neverPlayLanguages.
  ///
  /// In en, this message translates to:
  /// **'Never play languages'**
  String get neverPlayLanguages;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @folders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get folders;

  /// No description provided for @scanFolders.
  ///
  /// In en, this message translates to:
  /// **'Scan folders'**
  String get scanFolders;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @storageTemplate.
  ///
  /// In en, this message translates to:
  /// **'Storage template'**
  String get storageTemplate;

  /// No description provided for @blacklist.
  ///
  /// In en, this message translates to:
  /// **'Blacklist'**
  String get blacklist;

  /// No description provided for @whitelist.
  ///
  /// In en, this message translates to:
  /// **'Whitelist'**
  String get whitelist;

  /// No description provided for @rescanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Re-scan library'**
  String get rescanLibrary;

  /// No description provided for @tracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get tracks;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get genres;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @playlist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlist;

  /// No description provided for @queueTab.
  ///
  /// In en, this message translates to:
  /// **'Queues'**
  String get queueTab;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @mostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get mostPlayed;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @sortByTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortByTitle;

  /// No description provided for @sortByArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get sortByArtist;

  /// No description provided for @sortByAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get sortByAlbum;

  /// No description provided for @sortByDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get sortByDuration;

  /// No description provided for @sortByAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get sortByAdded;

  /// No description provided for @sortByPlays.
  ///
  /// In en, this message translates to:
  /// **'Play count'**
  String get sortByPlays;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @searchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Search library'**
  String get searchLibrary;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @selectItems.
  ///
  /// In en, this message translates to:
  /// **'Select items'**
  String get selectItems;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @tagEditor.
  ///
  /// In en, this message translates to:
  /// **'Tag editor'**
  String get tagEditor;

  /// No description provided for @tagEditorDesc.
  ///
  /// In en, this message translates to:
  /// **'Batch-edit metadata for {count} tracks'**
  String tagEditorDesc(int count);

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get fieldArtist;

  /// No description provided for @fieldAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get fieldAlbum;

  /// No description provided for @fieldAlbumArtist.
  ///
  /// In en, this message translates to:
  /// **'Album artist'**
  String get fieldAlbumArtist;

  /// No description provided for @fieldGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get fieldGenre;

  /// No description provided for @fieldYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get fieldYear;

  /// No description provided for @fieldTrackNumber.
  ///
  /// In en, this message translates to:
  /// **'Track number'**
  String get fieldTrackNumber;

  /// No description provided for @fieldDiscNumber.
  ///
  /// In en, this message translates to:
  /// **'Disc number'**
  String get fieldDiscNumber;

  /// No description provided for @fieldComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get fieldComment;

  /// No description provided for @fieldComposer.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get fieldComposer;

  /// No description provided for @fieldLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get fieldLanguage;

  /// No description provided for @fieldLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get fieldLyrics;

  /// No description provided for @fieldCover.
  ///
  /// In en, this message translates to:
  /// **'Cover art'**
  String get fieldCover;

  /// No description provided for @applyChanges.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get applyChanges;

  /// No description provided for @revertChanges.
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get revertChanges;

  /// No description provided for @audioCutter.
  ///
  /// In en, this message translates to:
  /// **'Audio cutter'**
  String get audioCutter;

  /// No description provided for @setAsRingtone.
  ///
  /// In en, this message translates to:
  /// **'Set as ringtone'**
  String get setAsRingtone;

  /// No description provided for @cutSelection.
  ///
  /// In en, this message translates to:
  /// **'Cut selection'**
  String get cutSelection;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyrics;

  /// No description provided for @lyricsSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced lyrics'**
  String get lyricsSynced;

  /// No description provided for @lyricsPlain.
  ///
  /// In en, this message translates to:
  /// **'Plain lyrics'**
  String get lyricsPlain;

  /// No description provided for @lyricsNone.
  ///
  /// In en, this message translates to:
  /// **'No lyrics found'**
  String get lyricsNone;

  /// No description provided for @lrcEditor.
  ///
  /// In en, this message translates to:
  /// **'LRC editor'**
  String get lrcEditor;

  /// No description provided for @stampLine.
  ///
  /// In en, this message translates to:
  /// **'Stamp timestamp'**
  String get stampLine;

  /// No description provided for @shiftLyrics.
  ///
  /// In en, this message translates to:
  /// **'Shift timings'**
  String get shiftLyrics;

  /// No description provided for @tagEditorApplied.
  ///
  /// In en, this message translates to:
  /// **'Tag changes applied'**
  String get tagEditorApplied;

  /// No description provided for @ringtoneSet.
  ///
  /// In en, this message translates to:
  /// **'Ringtone updated'**
  String get ringtoneSet;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String exportedTo(String path);

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Backup completed'**
  String get backupDone;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Restore completed'**
  String get restoreDone;

  /// No description provided for @onlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineTitle;

  /// No description provided for @spotifyStyle.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get spotifyStyle;

  /// No description provided for @news.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get news;

  /// No description provided for @discovery.
  ///
  /// In en, this message translates to:
  /// **'Discovery'**
  String get discovery;

  /// No description provided for @charts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get charts;

  /// No description provided for @whatsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s New in {version}'**
  String whatsNewTitle(String version);

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get updateAvailable;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'You are up to date'**
  String get upToDate;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @privacyFirst.
  ///
  /// In en, this message translates to:
  /// **'Privacy-first, plays only legal sources'**
  String get privacyFirst;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorTitle;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error — check your connection'**
  String get errorNetwork;

  /// No description provided for @errorStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage error — check permissions'**
  String get errorStorage;

  /// No description provided for @errorPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get errorPermission;

  /// No description provided for @permissionAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio access'**
  String get permissionAudio;

  /// No description provided for @permissionAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Required to scan your music library'**
  String get permissionAudioDesc;

  /// No description provided for @grantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grantPermission;

  /// No description provided for @queueMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge queues'**
  String get queueMerge;

  /// No description provided for @queueSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch queue'**
  String get queueSwitch;

  /// No description provided for @queueSave.
  ///
  /// In en, this message translates to:
  /// **'Save queue'**
  String get queueSave;

  /// No description provided for @queueReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get queueReorder;

  /// No description provided for @queueCount.
  ///
  /// In en, this message translates to:
  /// **'{count} queues'**
  String queueCount(int count);

  /// No description provided for @eqPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get eqPresets;

  /// No description provided for @eqFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get eqFlat;

  /// No description provided for @eqBassBoost.
  ///
  /// In en, this message translates to:
  /// **'Bass boost'**
  String get eqBassBoost;

  /// No description provided for @eqTreble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get eqTreble;

  /// No description provided for @eqVocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get eqVocal;

  /// No description provided for @eqRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get eqRock;

  /// No description provided for @eqJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get eqJazz;

  /// No description provided for @replayGain.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain'**
  String get replayGain;

  /// No description provided for @replayGainScan.
  ///
  /// In en, this message translates to:
  /// **'Scan loudness'**
  String get replayGainScan;

  /// No description provided for @replayGainMode.
  ///
  /// In en, this message translates to:
  /// **'ReplayGain mode'**
  String get replayGainMode;

  /// No description provided for @widgetSmall.
  ///
  /// In en, this message translates to:
  /// **'Wavely small widget'**
  String get widgetSmall;

  /// No description provided for @widgetControls.
  ///
  /// In en, this message translates to:
  /// **'Wavely playback widget'**
  String get widgetControls;

  /// No description provided for @widgetLarge.
  ///
  /// In en, this message translates to:
  /// **'Wavely album widget'**
  String get widgetLarge;

  /// No description provided for @qsTileLabel.
  ///
  /// In en, this message translates to:
  /// **'Wavely play/pause'**
  String get qsTileLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
