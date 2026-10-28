# Stage 2.1 — Online source contract tests

How to run the shared SourceProvider contract suite and the live
Navidrome contract test.

## Two layers

1. **Mocked contract suite** (runs anywhere, no infrastructure):
   - shared suite: `test/sources/source_contract.dart`
     (`runSourceProviderContract`), applied by:
     - `test/sources/subsonic/subsonic_source_test.dart` (scripted dio
       `HttpClientAdapter`)
     - `test/sources/jamendo/jamendo_source_test.dart`
     - `test/sources/archive_org/archive_org_source_test.dart`
     - `test/sources/fma/fma_source_test.dart` (with
       `expectsStreamFailure: true` — FMA's honest no-streaming contract)
   - fixtures committed under `test/fixtures/{jamendo,archive_org,fma}/`
     (`jamendo/track_search.json`, `archive_org/search.json`,
     `archive_org/item_metadata.json`, `fma/download_overlay.html`).

   Run:
   ```bash
   flutter test test/sources/
   ```

2. **Live Navidrome contract test** (needs Docker):
   - test file: `test/sources/subsonic/navidrome_contract_test.dart`
   - fixture: `docker-compose.navidrome.yml` (Navidrome 0.54.4, port 4533,
     health check on `/ping`, auto-created admin user
     `admin` / `wavely-ci-password`)

## Local run

```bash
# 1. seed some music (CI generates a sine-wave mp3; any audio works)
mkdir -p docker/navidrome/music
ffmpeg -f lavfi -i "sine=frequency=440:duration=5" \
  -codec:a libmp3lame -b:a 128k \
  docker/navidrome/music/Wavely_CI_Tone.mp3

# 2. start the server
docker compose -f docker-compose.navidrome.yml up -d
# wait for the health check to pass, then:

# 3. run the contract test (env vars pick up the server)
NAVIDROME_URL=http://localhost:4533 \
NAVIDROME_USER=admin \
NAVIDROME_PASSWORD=wavely-ci-password \
flutter test test/sources/subsonic/

# 4. tear down
docker compose -f docker-compose.navidrome.yml down -v
```

Note: the Navidrome tests are declared with `skip:` guards so a plain
`flutter test test/sources/` never fails on a machine without Docker. The
CI workflow (`.github/workflows/navidrome-contract.yml`) passes the env
vars explicitly and runs only `test/sources/subsonic/`.

## What the live contract asserts

- `ping.view` answers `status: ok` with an API version.
- `search3.view` finds the seeded track and returns mappable `Child`s.
- A garbage query returns an empty list (empty success, not an error).
- `stream.view` URL construction carries the id and `format=raw`.
- An unknown song id produces the protocol error shape
  (`SourceApiException`), never a crash.
- Transport sanity: the server answers HTTP (status < 500).

## Auth note

The Subsonic source uses the salted token scheme
(`t = md5(password + salt)`, salt regenerated per request). The unit test
`subsonic_source_test.dart` asserts the raw password never appears in any
query string.
