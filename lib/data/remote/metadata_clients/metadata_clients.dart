// Barrel for the Stage 1.2 metadata clients.
//
// Feature code imports this single entry point; the shared HTTP plumbing
// (User-Agent, rate limiter, caching GET) lives in
// `package:wavely/data/remote/metadata_http.dart`.

export 'archive_org_client.dart';
export 'deezer_client.dart';
export 'musicbrainz_client.dart';
export 'news_service.dart';
export 'reddit_client.dart';
export 'rss_client.dart';
export 'wikipedia_client.dart';
