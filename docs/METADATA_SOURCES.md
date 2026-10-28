# Stage 1.2 — Metadata sources (B1)

All endpoints below were verified LIVE on 2026-10-27 with
`User-Agent: Wavely/1.0 (https://github.com/Dani-Devlop/Music_Wavely)`
unless the row says otherwise. Metadata only — no playback, no downloads.

| Source | Endpoint | No-key? | Rate limit | Cache TTL | Fallback | Feature |
|---|---|---|---|---|---|---|
| MusicBrainz | `GET https://musicbrainz.org/ws/2/artist?query=<q>&fmt=json&limit=N` | ✅ (UA required) | 1 req/s (MB policy; enforced client-side) | 6 h | Deezer search | discovery, artist MBID resolution |
| MusicBrainz | `GET https://musicbrainz.org/ws/2/release-group?artist=<mbid>&type=album&fmt=json&limit=N&sort=first-release-date+desc` | ✅ | 1 req/s | 6 h | empty section | new-from-followed-artists |
| Deezer | `GET https://api.deezer.com/search/artist?q=<q>&limit=N` | ✅ | 5 req/s | 6 h | MusicBrainz | Because-you-listen-to seeding |
| Deezer | `GET https://api.deezer.com/artist/<id>/related?limit=N` | ✅ (search verified live; `/related` returned Access-Denied from THIS sandbox IP — client treats any failure as empty Result and the section degrades gracefully) | 5 req/s | 6 h | hide section | related artists |
| Deezer | `GET https://api.deezer.com/album/<id>` | ✅ | 5 req/s | 6 h | hide card | album metadata |
| Wikipedia | `GET https://en.wikipedia.org/api/rest_v1/page/summary/<title>` | ✅ (UA required) | polite: 1 req/s | 24 h | hide bio | artist detail bio |
| archive.org | `GET https://archive.org/advancedsearch.php?q=<q>&fl[]=identifier&rows=N&page=1&output=json` | ✅ | polite: 1 req/s | 24 h | hide section | free-catalog discovery (metadata only) |
| Reddit | `GET https://www.reddit.com/r/Music/new.json?limit=N` | ✅ in principle; this sandbox received an HTML bot-page instead of JSON — the client validates `content-type: application/json` and degrades to an empty Result | ~1 req/2s | 1 h | hide section | music news (metadata) |
| Pitchfork RSS | `https://pitchfork.com/feed/feed-news/rss` (301 → follows to final URL) | ✅ | 1 req/5 min | 1 h | hide section | reviews/news headlines |
| NME RSS | `https://www.nme.com/rss/news` | ✅ (HTTP 200 verified) | 1 req/5 min | 1 h | hide section | news headlines |
| Jamendo | `GET https://api.jamendo.com/v3.0/tracks/?format=json` WITHOUT client_id | ❌ **key REQUIRED** — live check returned `code:5 Invalid Client Id` | n/a | n/a | feature flag `WavelyEnv.hasJamendo` | Stage 2.1 source (NOT Stage 1.2) |

## Client architecture (`lib/data/remote/metadata_clients/`)

- One file per source, one shared contract: each client exposes
  `Future<Result<T>> fetch...()` and NEVER throws — all failures become
  `Result.failure(Failure(...))`.
- Every client:
  - sends the canonical `User-Agent` (constant `MetadataHttp.userAgent`),
  - goes through `RateLimiter` (per-host token bucket; MB 1/s, Deezer 5/s),
  - reads through `HttpCacheDao` (TTL per table above; offline → cached body
    if present, else failure),
  - parses defensively (`jsonDecode` guarded; any malformed payload →
    failure, not exception).
- Shared contract test (`test/data/remote/metadata_clients/contract_test.dart`)
  runs every client against a canned-response fake adapter and asserts:
  result-not-throw, cache write, cache read, offline fallback, UA header.
- Reddit/RSS clients use `http` (no Dio retrofit dependency); MB/Deezer/
  Wikipedia use Dio with the same adapter injection for tests.

## Stage 2.1 appendix — live-verified online source endpoints (this session)

Verified from the sandbox with curl during the Stage 2.1 session; re-verify
at owner local-verification time if in doubt.

### Jamendo (`lib/sources/jamendo/`)

- `GET https://api.jamendo.com/v3.0/tracks/?format=json&limit=2` **without a
  `client_id`** → HTTP 200 but body `headers.status = "failed", code 5`
  ("Invalid Client Id Error"). The API always answers 200; the envelope
  carries the failure.
- The historical public demo id `56d30c95` → `code 11`
  ("Suspended Application Error").
- Conclusion: Jamendo is **not usable anonymously**. Wavely requires the
  user to register a client id at developer.jamendo.com and store it in the
  Sources settings (persisted in SharedPreferences, no secret class).
- Endpoints used by the provider: `GET /v3.0/tracks/?search={q}`,
  `GET /v3.0/tracks/?id={id}`; stream = `audio` field, download =
  `audiodownload` field, license = `license_ccurl` field.
- Rate limit: 2 req/s enforced by the shared `RateLimiter` (500 ms).

### archive.org (`lib/sources/archive_org/`)

- `GET https://archive.org/advancedsearch.php?q={q}+AND+mediatype:(audio)
  &fl[]=identifier,title,creator,year&rows=50&output=json` → HTTP 200,
  anonymous, `response.docs[]` with the requested fields. `creator` may be
  a string OR a list; `year` may be a string OR a number (both handled).
- `GET https://archive.org/metadata/{identifier}` → HTTP 200, anonymous,
  `metadata{}` + `files[]` (`name`, `format`, `title`, `length`, `size`).
  `length` is `mm:ss` or fractional seconds (both parsed).
- File URL: `https://archive.org/download/{identifier}/{filename}`
  (URL-encoded filename).
- Quality preference implemented: Flac > VBR MP3 > Ogg Vorbis > any other
  audio extension.

### Free Music Archive (`lib/sources/fma/`)

- Legacy JSON API `https://freemusicarchive.org/api/trackSearch` and
  `/api/get/tracks.json` → **404** (dead). Not used.
- Search page `GET https://freemusicarchive.org/search?quicksearch={q}` →
  HTTP 200 HTML with parseable per-row anchors: `/track/<slug>` (title),
  `/artist/<slug>` (artist), a `HH:MM` duration span, and
  `data-url=".../track/<slug>/downloadOverlay/"` download links.
- `GET .../track/{slug}/downloadOverlay/` → HTTP 200 HTML containing the
  Creative-Commons license URL (e.g.
  `https://creativecommons.org/licenses/by-nc-sa/3.0/`) and the per-track
  download anchor `.../track/{slug}/download/`.
- Following `.../track/{slug}/download/` → **302 → /login**: downloads are
  gated behind an FMA account. Wavely does not scrape or bypass account
  walls, so `FmaSource.supportsStreaming/supportsDownload` are `false` and
  `resolveStream`/`download` throw a documented `SourceApiException`.
- `robots.txt` (verified this session): no `User-agent: *` block; only
  specific AI crawlers are disallowed. The provider still self-limits to
  1 request / 2 s via `RateLimiter`.

### Subsonic / Navidrome (`lib/sources/subsonic/`)

- Self-hosted protocol (Subsonic REST API v1.16.1); no public endpoint was
  live-verified from the sandbox (none exists anonymously). The contract
  test runs against a real Navidrome via `docker-compose.navidrome.yml`
  (see docs/SOURCES_CONTRACT_TESTS.md).
- Auth: salted token scheme `t = md5(password + salt)`; the clear-text
  password never appears in a URL.
