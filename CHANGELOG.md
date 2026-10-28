# Changelog

All notable changes to Wavely. Format based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0-dev] - Unreleased

### Stage 1.1 — Local Player Core
- Local library scan, playback, synced lyrics, search, settings, app shell

### Stage 1.2 — Auth, Sync, AI, Parental, Analytics, Discovery
- Supabase auth (email + Telegram), sync engine, AI chat, parental control,
  advanced shuffle, analytics, onboarding wizard, discovery metadata

### Stage 2.1 — Legal Online Sources + Download Manager
- Subsonic/Navidrome, Jamendo, archive.org, FMA providers
- Unified search, download manager with folder templates + provenance

### Stage 2.2 — News, Telegram Mini App, PWA, Desktop Packaging
- News: Reddit JSON + Pitchfork/NME/custom RSS, keyword classifier,
  offline cache via the existing http_cache (30-min TTL)
- Telegram Mini App: dart:js_interop bridge, HMAC-validated initData edge
  function, theme adapter, compile-time TELEGRAM_MODE
- PWA: manifest + placeholder icons, service worker (shell precache +
  SWR metadata cache, audio never cached), Media Session wiring,
  iOS guidance banner
- Desktop: MSIX config (unsigned), Flatpak manifest + .desktop,
  GitHub-Releases auto-update check, tag-driven release workflow
- Docs: TELEGRAM_MINIAPP, PACKAGING, PRIVACY, CONTRIBUTING; LICENSE
  copyright → Dani-Devlop
- Authored on `feat/stage-2.2` (was absent before Stage 2.2 authoring —
  see `docs/STAGE_2_2_REPORT.md`); awaiting owner local verification

### Pending
- Local verification: `flutter pub get` + `build_runner` + `flutter analyze`
  + `flutter test` have **never been run** (no Flutter SDK in the authoring
  sandbox) — see `docs/FINAL_VERIFICATION.md` for the copy-paste flow
- First-run fixes from that verification
- Stage 2.2 implementation
