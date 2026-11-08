// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appName => 'ولی';

  @override
  String get tabHome => 'خانه';

  @override
  String get tabLocal => 'محلی';

  @override
  String get tabOnline => 'آنلاین';

  @override
  String get tabSearch => 'جست‌وجو';

  @override
  String get tabSettings => 'تنظیمات';

  @override
  String get play => 'پخش';

  @override
  String get pause => 'توقف';

  @override
  String get next => 'بعدی';

  @override
  String get previous => 'قبلی';

  @override
  String get shuffle => 'پخش تصادفی';

  @override
  String get repeat => 'تکرار';

  @override
  String get repeatOff => 'بدون تکرار';

  @override
  String get repeatAll => 'تکرار همه';

  @override
  String get repeatOne => 'تکرار یک آهنگ';

  @override
  String get addToQueue => 'افزودن به صف';

  @override
  String get playNext => 'پخش بعدی';

  @override
  String get stopAfter => 'پس از این آهنگ متوقف شو';

  @override
  String get openQueue => 'بازکردن صف';

  @override
  String get queue => 'صف';

  @override
  String get nothingPlaying => 'چیزی در حال پخش نیست';

  @override
  String get openQueueHint => 'بازکردن صف';

  @override
  String get sleepTimer => 'تایمر خواب';

  @override
  String get sleepTimerOff => 'خاموش';

  @override
  String get sleepTimerEndOfTrack => 'پایان آهنگ';

  @override
  String sleepTimerIn(String duration) {
    return 'در $duration';
  }

  @override
  String get seekBarLabel => 'پیشرفت پخش';

  @override
  String get bookmarks => 'نشان‌ها';

  @override
  String get addBookmark => 'افزودن نشان';

  @override
  String get abRepeat => 'تکرار A-B';

  @override
  String get speed => 'سرعت';

  @override
  String get settingsTitle => 'تنظیمات';

  @override
  String get appearance => 'ظاهر';

  @override
  String get themeMode => 'حالت پوسته';

  @override
  String get themeSystem => 'سیستم';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeDark => 'تیره';

  @override
  String get accentColor => 'رنگ تأکیدی';

  @override
  String get accentPurple => 'بنفش';

  @override
  String get accentGreen => 'سبز';

  @override
  String get reduceTransparency => 'کاهش شفافیت';

  @override
  String get reduceTransparencyDesc => 'افکت‌های بلور را خاموش می‌کند';

  @override
  String get amoledBlack => 'مشکی آمولد';

  @override
  String get amoledBlackDesc => 'سطوح کاملاً مشکی در حالت تیره';

  @override
  String get adaptiveAccent => 'رنگ تأکیدی از جلد آلبوم';

  @override
  String get adaptiveAccentDesc => 'پوسته را هم‌رنگ جلد در حال پخش می‌کند';

  @override
  String get blurStrength => 'شدت بلور';

  @override
  String get blurOff => 'خاموش';

  @override
  String get cornerRadius => 'گردی گوشه‌ها';

  @override
  String get language => 'زبان';

  @override
  String get languageSystem => 'پیش‌فرض سیستم';

  @override
  String get languageEnglish => 'انگلیسی';

  @override
  String get languagePersian => 'فارسی';

  @override
  String get playback => 'پخش';

  @override
  String get equalizerEffects => 'اکولایزر و افکت‌ها';

  @override
  String get equalizerEffectsDesc =>
      'اکولایزر، تقویت باس، ریورب، ریپلی‌گین و پروفایل‌های هر دستگاه';

  @override
  String get crossfade => 'کراس‌فید';

  @override
  String get gaplessPlayback => 'پخش بدون فاصله';

  @override
  String get resumeOnStart => 'ادامه پخش هنگام شروع';

  @override
  String get speedSection => 'سرعت پخش';

  @override
  String get neverPlayLanguages => 'هرگز پخش نشوند (زبان‌ها)';

  @override
  String get library => 'کتابخانه';

  @override
  String get folders => 'پوشه‌ها';

  @override
  String get scanFolders => 'پوشه‌های اسکن';

  @override
  String get storage => 'حافظه';

  @override
  String get storageTemplate => 'قالب ذخیره‌سازی';

  @override
  String get blacklist => 'لیست سیاه';

  @override
  String get whitelist => 'لیست سفید';

  @override
  String get rescanLibrary => 'اسکن دوباره کتابخانه';

  @override
  String get tracks => 'آهنگ‌ها';

  @override
  String get albums => 'آلبوم‌ها';

  @override
  String get artists => 'هنرمندان';

  @override
  String get genres => 'ژانرها';

  @override
  String get playlists => 'سیاهه‌ها';

  @override
  String get playlist => 'سیاهه';

  @override
  String get queueTab => 'صف‌ها';

  @override
  String get favorites => 'علاقه‌مندی‌ها';

  @override
  String get recent => 'اخیر';

  @override
  String get mostPlayed => 'بیشترین پخش';

  @override
  String get sort => 'مرتب‌سازی';

  @override
  String get sortByTitle => 'عنوان';

  @override
  String get sortByArtist => 'هنرمند';

  @override
  String get sortByAlbum => 'آلبوم';

  @override
  String get sortByDuration => 'مدت';

  @override
  String get sortByAdded => 'به‌تازگی افزوده‌شده';

  @override
  String get sortByPlays => 'تعداد پخش';

  @override
  String get sortAscending => 'صعودی';

  @override
  String get sortDescending => 'نزولی';

  @override
  String get searchLibrary => 'جست‌وجو در کتابخانه';

  @override
  String get noResults => 'نتیجه‌ای یافت نشد';

  @override
  String get selectItems => 'انتخاب موارد';

  @override
  String get selectAll => 'انتخاب همه';

  @override
  String get clearSelection => 'پاک‌کردن انتخاب';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'لغو';

  @override
  String get confirm => 'تأیید';

  @override
  String get save => 'ذخیره';

  @override
  String get close => 'بستن';

  @override
  String get continueAction => 'ادامه';

  @override
  String get retry => 'تلاش دوباره';

  @override
  String get done => 'انجام شد';

  @override
  String get edit => 'ویرایش';

  @override
  String get remove => 'برداشتن';

  @override
  String get exportAction => 'برون‌بری';

  @override
  String get importAction => 'درون‌ریزی';

  @override
  String get tagEditor => 'ویرایشگر تگ';

  @override
  String tagEditorDesc(int count) {
    return 'ویرایش گروهی فراداده برای $count آهنگ';
  }

  @override
  String get fieldTitle => 'عنوان';

  @override
  String get fieldArtist => 'هنرمند';

  @override
  String get fieldAlbum => 'آلبوم';

  @override
  String get fieldAlbumArtist => 'هنرمند آلبوم';

  @override
  String get fieldGenre => 'ژانر';

  @override
  String get fieldYear => 'سال';

  @override
  String get fieldTrackNumber => 'شماره آهنگ';

  @override
  String get fieldDiscNumber => 'شماره دیسک';

  @override
  String get fieldComment => 'یادداشت';

  @override
  String get fieldComposer => 'آهنگساز';

  @override
  String get fieldLanguage => 'زبان';

  @override
  String get fieldLyrics => 'متن آهنگ';

  @override
  String get fieldCover => 'جلد';

  @override
  String get applyChanges => 'اعمال تغییرات';

  @override
  String get revertChanges => 'بازگردانی';

  @override
  String get audioCutter => 'برش صدا';

  @override
  String get setAsRingtone => 'تنظیم به‌عنوان زنگ';

  @override
  String get cutSelection => 'برش بخش انتخاب‌شده';

  @override
  String get lyrics => 'متن آهنگ';

  @override
  String get lyricsSynced => 'متن همگام‌شده';

  @override
  String get lyricsPlain => 'متن ساده';

  @override
  String get lyricsNone => 'متن آهنگی یافت نشد';

  @override
  String get lrcEditor => 'ویرایشگر LRC';

  @override
  String get stampLine => 'درج زمان‌سنج';

  @override
  String get shiftLyrics => 'جابه‌جایی زمان‌ها';

  @override
  String get tagEditorApplied => 'تغییرات تگ اعمال شد';

  @override
  String get ringtoneSet => 'زنگ به‌روزرسانی شد';

  @override
  String exportedTo(String path) {
    return 'برون‌بری به $path';
  }

  @override
  String get backupDone => 'پشتیبان‌گیری انجام شد';

  @override
  String get restoreDone => 'بازیابی انجام شد';

  @override
  String get onlineTitle => 'آنلاین';

  @override
  String get spotifyStyle => 'مرور';

  @override
  String get news => 'اخبار';

  @override
  String get discovery => 'کشف موسیقی';

  @override
  String get charts => 'جدول‌ها';

  @override
  String whatsNewTitle(String version) {
    return 'تازگی‌های نسخه $version';
  }

  @override
  String get updateAvailable => 'به‌روزرسانی موجود است';

  @override
  String get checkForUpdates => 'بررسی به‌روزرسانی';

  @override
  String get upToDate => 'به‌روز هستید';

  @override
  String get about => 'درباره';

  @override
  String get version => 'نسخه';

  @override
  String get privacyFirst => 'اول‌ویت با حریم خصوصی؛ فقط منابع قانونی';

  @override
  String get errorTitle => 'مشکلی پیش آمد';

  @override
  String get errorGeneric => 'خطای غیرمنتظره';

  @override
  String get errorNetwork => 'خطای شبکه — اتصال خود را بررسی کنید';

  @override
  String get errorStorage => 'خطای حافظه — مجوزها را بررسی کنید';

  @override
  String get errorPermission => 'مجوز رد شد';

  @override
  String get permissionAudio => 'دسترسی به صدا';

  @override
  String get permissionAudioDesc => 'برای اسکن کتابخانه موسیقی لازم است';

  @override
  String get grantPermission => 'اعطای مجوز';

  @override
  String get queueMerge => 'ادغام صف‌ها';

  @override
  String get queueSwitch => 'تعویض صف';

  @override
  String get queueSave => 'ذخیره صف';

  @override
  String get queueReorder => 'مرتب‌سازی دوباره';

  @override
  String queueCount(int count) {
    return '$count صف';
  }

  @override
  String get eqPresets => 'پیش‌تنظیم‌ها';

  @override
  String get eqFlat => 'مسطح';

  @override
  String get eqBassBoost => 'تقویت باس';

  @override
  String get eqTreble => 'زیر و بمبی (تربل)';

  @override
  String get eqVocal => 'خواننده';

  @override
  String get eqRock => 'راک';

  @override
  String get eqJazz => 'جاز';

  @override
  String get replayGain => 'ریپلی‌گین';

  @override
  String get replayGainScan => 'اسکن بلندی صدا';

  @override
  String get replayGainMode => 'حالت ریپلی‌گین';

  @override
  String get widgetSmall => 'ابزارک کوچک ولی';

  @override
  String get widgetControls => 'ابزارک پخش ولی';

  @override
  String get widgetLarge => 'ابزارک آلبوم ولی';

  @override
  String get qsTileLabel => 'پخش/توقف ولی';
}
