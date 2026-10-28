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
- **Not present — never authored or pushed.** No PR, no branch, and no
  Stage 2.2 artifacts exist in the repository (verified at close-out via the
  GitHub API). Planned scope only; must be built in a future session.
  See `docs/FINAL_VERIFICATION.md` §1.

### Pending
- Local verification: `flutter pub get` + `build_runner` + `flutter analyze`
  + `flutter test` have **never been run** (no Flutter SDK in the authoring
  sandbox) — see `docs/FINAL_VERIFICATION.md` for the copy-paste flow
- First-run fixes from that verification
- Stage 2.2 implementation
