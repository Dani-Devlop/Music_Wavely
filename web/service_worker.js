/*
 * Wavely service worker (Stage 2.2).
 *
 * Strategy:
 * - App shell (index, bootstrap, main.dart.js, manifest, icons) is
 *   precached on install so the PWA boots offline.
 * - Metadata API responses (lrclib.net, api.deezer.com, musicbrainz.org,
 *   api.jamendo.com, archive.org) use stale-while-revalidate with a
 *   30-minute freshness window.
 * - AUDIO STREAMS AND DOWNLOADS ARE NEVER CACHED (Range requests break
 *   cached responses; legal-source streams must not be stored).
 */

const CACHE_SHELL = 'wavely-shell-v1';
const CACHE_METADATA = 'wavely-metadata-v1';
const METADATA_TTL_MS = 30 * 60 * 1000; // 30 minutes

const SHELL_ASSETS = [
  '/',
  'manifest.json',
  'flutter_bootstrap.js',
  'main.dart.js',
  'icons/icon-48.png',
  'icons/icon-72.png',
  'icons/icon-96.png',
  'icons/icon-144.png',
  'icons/icon-192.png',
  'icons/icon-256.png',
  'icons/icon-384.png',
  'icons/icon-512.png',
];

const METADATA_HOSTS = [
  'lrclib.net',
  'api.deezer.com',
  'musicbrainz.org',
  'api.jamendo.com',
  'archive.org',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_SHELL)
      .then((cache) =>
        // addAll fails the whole install if ONE asset 404s (main.dart.js
        // only exists after a release build) — tolerate per-asset failures.
        Promise.all(
          SHELL_ASSETS.map((asset) =>
            cache.add(new Request(asset, { cache: 'reload' })).catch(() => {}),
          ),
        ),
      )
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_SHELL && key !== CACHE_METADATA)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') {
    return;
  }
  const url = new URL(request.url);

  // NEVER cache audio streams or downloads (Range/206 semantics).
  if (request.destination === 'audio' || request.destination === 'media') {
    return;
  }
  if (/\.(mp3|flac|ogg|opus|wav|m4a)(\?|$)/i.test(url.pathname)) {
    return;
  }
  if (/(\/stream|\/download|\/getCoverArt)/i.test(url.pathname)) {
    return;
  }

  // App shell: cache-first, network fallback.
  if (url.origin === self.location.origin) {
    event.respondWith(
      caches.match(request).then(
        (hit) =>
          hit ||
          fetch(request).then((response) => {
            const copy = response.clone();
            caches
              .open(CACHE_SHELL)
              .then((cache) => cache.put(request, copy))
              .catch(() => {});
            return response;
          }),
      ),
    );
    return;
  }

  // Metadata APIs: stale-while-revalidate with a 30-minute window.
  if (METADATA_HOSTS.some((host) => url.hostname === host || url.hostname.endsWith('.' + host))) {
    event.respondWith(
      caches.open(CACHE_METADATA).then(async (cache) => {
        const cached = await cache.match(request);
        const fresh = cached && cached.headers.get('sw-fetched-at');
        const age = fresh ? Date.now() - Number(fresh) : Infinity;
        const network = fetch(request)
          .then((response) => {
            if (response.ok) {
              const copy = response.clone();
              const headers = new Headers(copy.headers);
              headers.set('sw-fetched-at', String(Date.now()));
              const stamped = new Response(copy.body, {
                status: copy.status,
                statusText: copy.statusText,
                headers,
              });
              cache.put(request, stamped).catch(() => {});
            }
            return response;
          })
          .catch(() => cached);
        return age < METADATA_TTL_MS && cached ? cached : network;
      }),
    );
  }
});
