# Stage 2.1 — Download folder templates

The download manager renders target directories from a user-editable
template (`DownloadSettingsScreen → Folder template`) using
`lib/features/downloads/domain/folder_template.dart`.

## Default

```
Music/{continent}/{country}/{genre}
```

(Stored in SharedPreferences under `downloads.folderTemplate`; the empty
value falls back to this default. `DownloadPrefs.FolderTemplateDefault`
must stay in sync with `FolderTemplate.defaultTemplate` — a test asserts
both spellings.)

## Placeholders

| Placeholder     | Source                                                        | Fallback       |
| --------------- | ------------------------------------------------------------- | -------------- |
| `{continent}`   | MusicBrainz artist origin `area` mapped through `ArtistGeoResolver.continentForArea` (static area→continent map over common MusicBrainz areas) | `Unknown`      |
| `{country}`     | MusicBrainz artist origin `area` name (free-form, not an ISO code — documented limitation) | `Unknown`      |
| `{genre}`       | `Track.genre`                                                 | `Unknown`      |
| `{artist}`      | `Track.artistOrUnknown`                                       | `Unknown Artist` |
| `{album}`       | `Track.album`                                                 | `Unknown`      |
| `{year}`        | `Track.addedAt.year` (the Track entity has no release-year field; documented limitation) | download year  |
| `{title}`       | `Track.title`                                                 | — (required)   |
| `{trackNumber}` | Stage 2.1 constant `00` (Track has no track-number field; documented limitation) | `00`           |

## Rendering rules

1. Every placeholder is substituted before splitting.
2. The rendered string is split on `/`; empty segments are dropped (paths
   never contain `//`).
3. Each segment runs through the filename sanitizer
   (`lib/features/downloads/domain/filename_sanitizer.dart`): Windows
   illegal characters `<>:"/\|?*` and control chars become `_`, trailing
   dots/spaces are trimmed, reserved device names get a `_` suffix, unicode
   is preserved, and segments are clamped to 200 chars.
4. The final target path is `<baseDir>/<rendered template>/<title>.<ext>`
   — the quality value is stored per row in the `downloads.quality`
   column, not in the path (the template is the whole directory contract).
5. Geography is cached per artist inside the resolver instance
   (`DownloadService` builds one per service instance), so MusicBrainz is
   queried at most once per artist per session. Resolver failures (network
   down, rate limited) degrade to `Unknown` — never an exception.

## Examples

Template `Music/{continent}/{country}/{genre}`, track
"Aurora" by "Nova" (genre Ambient, MusicBrainz area Germany):

```
/storage/wavely/Music/Europe/Germany/Ambient/Aurora.flac
```

Same track with no MusicBrainz match:

```
/storage/wavely/Music/Unknown/Unknown/Ambient/Aurora.flac
```

Template `{artist}/{album}/{year}`, track "First Song" on album
"North", added 2024:

```
/storage/wavely/Nova/North/2024/First Song.mp3
```

## Provenance sidecar

Next to every completed download, `<sourceTrackId>.wavely.json` is written
into the same directory:

```json
{
  "source": "jamendo",
  "sourceId": "aur-99",
  "url": "https://cdn.example.com/aurora.flac",
  "license": "https://creativecommons.org/licenses/by/4.0/",
  "downloadedAt": "2026-01-30T12:00:00.000Z",
  "quality": "original",
  "checksum": "sha256:<64 hex chars>"
}
```

The same JSON is mirrored into the `downloads.provenanceJson` DB column.
