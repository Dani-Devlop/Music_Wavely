# Privacy policy — Wavely

_Last updated: Stage 2.2._

Wavely is privacy-first by construction: the local player core works with
**zero accounts, zero keys and zero telemetry**.

## What Wavely collects

- **Nothing for playback.** Local library scanning, playback, lyrics and
  search happen entirely on-device (SQLite via Drift).
- **Crash reports (opt-in).** When the owner builds with a `SENTRY_DSN`,
  crash-only reporting is enabled with `sendDefaultPii = false`,
  `tracesSampleRate = 0`, no session tracking, and path-like breadcrumbs
  stripped before upload (see `lib/app/bootstrap.dart`). No analytics, no
  product telemetry, no ads.
- **Accounts (opt-in).** Email and Telegram sign-in (Stage 1.2/2.2) exist
  only to sync *your* play history across *your* devices via Supabase.
  Telegram sign-in sends the raw `initData` string to the Wavely edge
  function, which validates it server-side and never logs it.

## What Wavely does NOT do

- No DRM circumvention, no unofficial paid-service APIs, no scraping of
  paid-catalog audio (hard project rule).
- No listening-profile selling, no ad SDKs, no third-party trackers.
- Online sources used (Subsonic/Navidrome self-hosted, Jamendo,
  archive.org, FMA metadata) are queried directly with a descriptive
  User-Agent; requests carry no user identifiers beyond what those
  services' own terms require.

## Data deletion

- **Local data:** Settings → Clear cache removes cached HTTP responses
  and cover art; uninstalling removes the database (plays, downloads,
  lyrics cache, news articles).
- **Account data:** deleting the Supabase account (Auth → user deletion;
  the Telegram mapping is derived, so removing the account removes the
  identity link) deletes the synced play history. A self-serve delete
  endpoint is planned; until then, open an issue on
  `github.com/Dani-Devlop/Music_Wavely` and the owner will process the
  deletion.
- **News feature (Stage 2.2):** article metadata is cached on-device only
  and never leaves the device; muted sources and category preferences are
  local prefs.

## Permissions (per platform)

- Android: storage access for the local library scan, notifications for
  download progress (both are feature-scoped and degrade when denied).
- Desktop: filesystem (library + downloads), network.
- Web/PWA: network only; no local file scan (documented limitation).
- Telegram Mini App: the platform's `initData` identity only.
