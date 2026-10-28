import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:wavely/data/local/db/database_provider.dart';
import 'package:wavely/data/remote/metadata_http.dart';
import 'package:wavely/features/news/data/news_prefs.dart';
import 'package:wavely/features/news/data/news_service.dart';
import 'package:wavely/features/settings/data/settings_provider.dart';

/// SharedPreferences-backed news settings.
final newsPrefsProvider = Provider<NewsPrefs>((ref) {
  return NewsPrefs(ref.watch(sharedPrefsProvider));
});

/// The news aggregator singleton over the shared database + HTTP cache.
final newsServiceProvider = FutureProvider<NewsService>((ref) async {
  final db = ref.watch(databaseProvider);
  return NewsService(
    dao: db.newsDao,
    prefs: ref.watch(newsPrefsProvider),
    http: CachingHttpClient(cacheDao: db.httpCacheDao),
  );
});
