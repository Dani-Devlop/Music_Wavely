<div align="center">

# 🎵 Wavely

**Your music, your way. Cross-platform, offline-first, and AI-powered.**

A free, open-source, glassmorphic music player for **legal sources only** —
your local files, your own Subsonic/Navidrome server, and free catalogs
(Jamendo, Free Music Archive, archive.org). No ads, no paywall, no PII
tracking.

[![CI — Full Verification](https://github.com/Dani-Devlop/Music_Wavely/actions/workflows/verify.yml/badge.svg)](https://github.com/Dani-Devlop/Music_Wavely/actions/workflows/verify.yml)
[![Release — v1.0.1-beta](https://img.shields.io/badge/version-1.0.1--beta-8b5cf6)](https://github.com/Dani-Devlop/Music_Wavely/releases/tag/v1.0.1-beta)
[![Tests](https://img.shields.io/badge/tests-1544%20passing-brightgreen)](https://github.com/Dani-Devlop/Music_Wavely/actions/workflows/verify.yml)
[![E2E](https://img.shields.io/badge/E2E-verified-10b981)](.github/workflows/e2e.yml)
[![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-informational)](#getting-started)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

</div>

---

Wavely is a **privacy-first player** that works with **zero API keys** out of
the box: scan your local library and hit play. Want more? Point it at your own
Subsonic/Navidrome server, add a free Jamendo client id, or sign in with
Telegram/Email to sync across devices via Supabase. Spotify/Deezer/Apple are
**metadata-only** through official APIs — Wavely never touches paid-catalog
audio.

Every release is **E2E-verified on CI**: instrumented end-to-end scenarios
drive the real app — library scan → playback, synced lyrics, AI queue
building, parental censoring, download → offline playback — and the
screenshots below are rendered live from those runs.

## 📥 Download v1.0.1-Beta

Grab the latest build straight from the
[v1.0.1-beta release page](https://github.com/Dani-Devlop/Music_Wavely/releases/tag/v1.0.1-beta):

| Platform | Download | Requirements |
| --- | --- | --- |
| 🤖 **Android** | [**Universal APK**](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-android-universal.apk) — all ABIs | Android 8.0+ |
| | Slim per-device APKs: [arm64-v8a](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-android-arm64-v8a.apk) · [armeabi-v7a](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-android-armeabi-v7a.apk) · [x86_64](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-android-x86_64.apk) | |
| 🪟 **Windows** | [**Windows x64 (.zip)**](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-windows-x64.zip) — unzip and run `wavely.exe` | Windows 10 / 11, 64-bit |
| 🐧 **Linux** | [**AppImage**](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-linux-x64.AppImage) — chmod +x and run · [tar.gz](https://github.com/Dani-Devlop/Music_Wavely/releases/download/v1.0.1-beta/wavely-v1.0.1-beta-linux-x64.tar.gz) | glibc 2.31+ (Ubuntu 20.04+) |
| 🌐 **Web / other** | Build from source — see [🚀 Getting Started](#getting-started) | Flutter stable ≥ 3.35 |

> ℹ️ Android picks the right architecture automatically when you install the
> universal APK. The MSIX installer and Flatpak bundle are included in the
> release when their optional packaging steps succeed; AppImage/MSIX are
> unsigned unless signing secrets are configured
> ([docs/PACKAGING.md](docs/PACKAGING.md)).

## 📸 Screenshots

<p align="center">
  <img src="docs/assets/home.png" width="200" alt="Library home with live mini-player" />
  <img src="docs/assets/now_playing.png" width="200" alt="Now playing screen" />
  <img src="docs/assets/synced_lyrics.png" width="200" alt="Synced lyrics overlay with active-line highlight" />
  <img src="docs/assets/ai_chat.png" width="200" alt="AI chat building a queue" />
  <img src="docs/assets/settings.png" width="200" alt="Settings — appearance and playback" />
</p>
<p align="center">
  <sub>Library · Now Playing · Synced Lyrics (LRCLIB) · AI DJ Chat · Settings — rendered from the E2E suite on CI</sub>
</p>

## ✨ Features

### 🎧 Playback
- **Gapless** and **crossfade** transitions between tracks.
- **Background playback** on every platform, with a live mini-player and
  drag-to-reorder queue.
- **Sleep timer** with fade-out and playback-speed control.
- Three platform engines behind one contract: `just_audio` (Android),
  `media_kit` (Windows/Linux desktop), JS interop (Web).

### 🎛️ DAP features (v0.2.0)
- **Hi-Res audio output** — 24-bit / 192 kHz paths, no forced resampling
  anywhere in the chain ([docs/HIRES_AUDIO.md](docs/HIRES_AUDIO.md)).
- **USB / exclusive-mode bit-perfect output** — mpv `audio-exclusive` on
  desktop, AAudio exclusive on Android 14+
  ([docs/HIRES_AUDIO.md](docs/HIRES_AUDIO.md)).
- **10-band equalizer** — `just_audio` `AudioPipeline` on Android, `lavfi`
  EQ on desktop, per-device presets stored in SQLite
  ([docs/DAP_FEATURES.md](docs/DAP_FEATURES.md)).
- **Plugin support** — sandboxed, compile-time plugin host with the
  "Local Folders" reference plugin
  ([docs/DAP_FEATURES.md](docs/DAP_FEATURES.md)).

### 📚 Library & Sources
- **FLAC / MP3 / WAV / M4A / OGG** support with metadata and embedded artwork.
- **Folder scanning** with an FTS5-backed index for instant search.
- **Legal online sources only**: your own **Subsonic / Navidrome**,
  **Jamendo**, **Free Music Archive**, **archive.org**.
- Unified **local + online search** across all configured sources.
- Built-in **download manager** — folder templates, filename sanitizing,
  per-file provenance, Wi-Fi-only gate, and **true offline playback** of
  downloaded files.

### 🧠 Intelligence
- **AI DJ chat** — mood-based conversation that builds and reshapes the
  queue ("make me a chill mix" → a validated queue you can play or
  regenerate).
- **Synced lyrics** — embedded LRC first, then **LRCLIB** fallback, with
  auto-scroll, active-line highlighting, tap-to-seek and manual offset.

### 🛡️ Parental Controls
- **PIN-gated** management screen with an audit trail.
- **Blocked words** drive automatic **audio beeping (censoring)** through
  the offline ffmpeg pipeline — the original file is never modified.
- Artist / album / genre blocklists and a no-lyrics fail-safe policy
  (block · mute · allow).

### 🎨 UI/UX
- **Glassmorphism** design system with 13 reusable glass components.
- **Light/Dark themes** with purple/green accent pairs and reduce-
  transparency support.
- Responsive shell: mini player, now-playing screen, bottom navigation.
- Typography: **Sora** (headings) + **Inter** (body), bundled under the
  SIL Open Font License.

### ☁️ Auth & Sync
- **Telegram / Email login** (Telegram Mini App + PWA aware).
- **Supabase sync** of plays, follows, and settings across devices —
  offline-first with an outbox queue.
- Crash-only reporting — paths and PII are stripped from release logs.

## 🏗️ Architecture

```mermaid
flowchart TB
    subgraph ui["Flutter UI — lib/features"]
        screens["library · search · player · lyrics"]
        morefeat["downloads · discovery · news · settings"]
        smart["ai_chat (AI DJ) · parental · telegram"]
    end

    subgraph state["Riverpod — lib/app (code-generated providers)"]
        prov["providers · go_router shell · theme pair"]
    end

    subgraph domain["Domain — lib/domain"]
        ent["freezed entities · abstract contracts"]
        uc["use cases (ScanLibrary · SearchLocal)"]
    end

    subgraph data["Repositories — lib/data"]
        repo["repository implementations"]
        daos["DAOs: tracks · plays · lyrics · downloads · outbox"]
        drift[("Drift · SQLite + FTS5")]
    end

    subgraph remote["Remote sources — lib/sources"]
        subsonic["Subsonic / Navidrome"]
        catalogs["Jamendo · FMA · archive.org"]
        lrc["LRCLIB lyrics"]
        sb["Supabase auth + sync"]
    end

    subgraph playback["Playback — lib/playback"]
        qm["QueueManager: repeat · shuffle · sleep timer · persist"]
        ef["EngineFactory"]
        eng["just_audio (Android) · media_kit (desktop) · js_interop (web)"]
    end

    subgraph plugins["Plugins — lib/plugins"]
        phost["sandboxed plugin host"]
        lfp["Local Folders reference plugin"]
    end

    ui --> state --> domain
    uc --> repo --> daos --> drift
    domain --> remote
    ui --> playback
    qm --> ef --> eng
    state --> qm
    phost --> lfp
    state --> phost
```

## 🚀 Getting Started

**Prerequisites:** [Flutter](https://docs.flutter.dev/get-started/install)
stable ≥ 3.35 (Dart ^3.9). The platform runner folders (android/, windows/,
linux/, web/) are **not committed** — they are scaffolded locally:

```bash
git clone https://github.com/Dani-Devlop/Music_Wavely.git
cd Music_Wavely

# 1. Scaffold the platform runners (safe: existing files are never touched)
flutter config --enable-windows-desktop --enable-linux-desktop
flutter create . --platforms=android,windows,linux,web --org app.wavely --project-name wavely

# 2. Patch the Android runner for Wavely's plugin set (desugaring +
#    minSdk 26; no-op if you only scaffolded desktop targets)
python3 tools/patch_android_desugaring.py

# 3. Dependencies + code generation
flutter pub get
# 3b. home_widget ships jvmTarget 1.8 Kotlin that the compiler's inliner
#     rejects — raise it in the pub cache (run AFTER pub get)
python3 tools/patch_android_jvm_target.py
dart run build_runner build --delete-conflicting-outputs

# 4. Configuration — optional! The local player needs NO API keys at all.
cp .env.example .env   # add JAMENDO_CLIENT_ID / Subsonic / Supabase if you want them

# 5. Run
flutter run -d linux            # or -d windows, or an Android device id
```

| Platform | Build |
| --- | --- |
| **Android** | `flutter build apk --release` (or `--split-per-abi`) |
| **Windows** | `flutter build windows --release` |
| **Linux** | `flutter build linux --release` |
| **Web** | `flutter build web` |

## ✅ Verify (what CI does on every push)

```bash
flutter analyze                                            # 0 errors required
flutter test --coverage                                    # 1544 tests passing

# E2E scenarios + real-UI screenshots (the ARTEMIS-mirror suite):
flutter test test/e2e test/goldens

# Subsonic contract suite against a live Navidrome server:
docker compose -f docker-compose.navidrome.yml up -d
flutter test test/sources/subsonic/
docker compose -f docker-compose.navidrome.yml down -v
```

Every feature ships with tests; nothing is considered "done" unverified.
The [`e2e.yml`](.github/workflows/e2e.yml) workflow additionally builds a
debug APK in the cloud on every push.

## 📦 Releases

Pushing a `v*.*.*` tag triggers the release workflow, which builds:

| Platform | Artifacts |
| --- | --- |
| Android | `wavely-<tag>-android-universal.apk` + `armeabi-v7a` / `arm64-v8a` / `x86_64` ABI splits |
| Windows | `wavely-<tag>-windows-x64.zip` (+ signed MSIX when signing secrets are set) |
| Linux | `wavely-<tag>-linux-x64.tar.gz` (+ AppImage, + Flatpak when configured) |

Every asset ships with a `SHA256SUMS.txt` — see
[`docs/PACKAGING.md`](docs/PACKAGING.md) for local signing.

## 🗺️ Roadmap

- [x] **v0.1.0** — core player: library, playback engines, synced lyrics,
      online sources, downloads, auth & sync
- [x] **v0.2.0** — DAP stage: Hi-Res output, equalizer, plugin host,
      multi-arch release pipeline; Stage 5 cross-feature regression suite
- [x] **v1.0.0** — **stable**: instrumented E2E verification of the four
      critical user flows (library scan → playback, synced lyrics + AI
      queue, parental censoring, download → offline play), real-UI
      screenshot capture on CI, bundled Sora/Inter typography, cloud
      debug-APK pipeline
- [x] **v1.0.1-beta** — **Musicolet-parity beta**: 20 multi-queue system,
      9-tab library with QuickSearch & multi-select, precise seek/bookmarks/
      A-B repeat, sleep timer, 3-source lyrics + LRC editor, folder browser
      with blacklist, 13-field tag editor, audio cutter & ringtone setter,
      M3U + backup/restore, 5-band EQ + ReplayGain + crossfade/gapless/speed,
      lock-screen queue & lyrics, 3 home widgets, QS tile, Android Auto
      browse, headset FF/rewind rules, AMOLED/blur/accent theming, mini-player
      gestures, Persian + RTL localization, neon-glass logo & splash
- [ ] Plugin UI surface (management screen + declarative REST plugins)
- [ ] DSP extension surface (crossfeed, loudness normalization)

## 🤝 Contributing

Contributions are welcome — see
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). One non-negotiable ground
rule: **legal sources only**. No DRM circumvention, no unofficial paid-service
APIs, no scraping of paid-catalog audio; PRs violating this are closed
without review.

## 📚 Documentation

- [Final Verification Guide](docs/FINAL_VERIFICATION.md) — copy-paste local verify flow
- [Changelog](CHANGELOG.md) — keep-a-changelog style history
- [Privacy](docs/PRIVACY.md) · [Security Audit](docs/SECURITY_AUDIT.md) · [Packaging](docs/PACKAGING.md)
- [DAP Features](docs/DAP_FEATURES.md) · [Hi-Res Audio](docs/HIRES_AUDIO.md)
- Stage ledgers: [1.1](docs/STAGE_1_1_REPORT.md) · [1.2](docs/STAGE_1_2_REPORT.md) · [2.1](docs/STAGE_2_1_REPORT.md) · [2.2](docs/STAGE_2_2_REPORT.md) · [3](docs/STAGE_3_REPORT.md)

## 📄 License

Released under the [MIT License](LICENSE) — Copyright (c) 2026 Dani-Devlop.
The bundled **Sora** and **Inter** typefaces are distributed under the
[SIL Open Font License 1.1](https://openfontlicense.org/).

<div align="center">
<sub>Built with Flutter · Riverpod · Drift · media_kit · Supabase</sub>
</div>
