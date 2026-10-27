# MUSIC_LYRICS_EMBEDD — Inspection Report (Stage 1.1, item 8)

- **Repo inspected:** `https://github.com/Dani-Devlop/Music_Lyrics_Embedd`
- **Inspection date:** 2026-02-27 (Stage 1.1 build)
- **Inspected by:** automated Stage 1.1 build agent (on behalf of Dani-Devlop)

## 1. What the mandate required

> FIRST: clone the repo and inspect README, LICENSE, pubspec/package.json/
> requirements, entry points, deps. Write this report with findings, then decide:
> wrap as a provider (permissive license + clean deps), or extract only the LRC
> parser with attribution (GPL/unclear/heavy), never blocking the app on it.

## 2. Findings

| Check | Result |
|---|---|
| `git clone` | **FAILED** — repository not accessible |
| Repo web page (`github.com/Dani-Devlop/Music_Lyrics_Embedd`) | **HTTP 404** |
| `raw.githubusercontent.com/.../main/README.md` | **HTTP 404** |
| LICENSE | **UNAVAILABLE** — cannot be evaluated |
| pubspec / package.json / requirements | **UNAVAILABLE** |
| Entry points, dependency tree | **UNAVAILABLE** |

A GitHub 404 on clone means the repository is **private, renamed, deleted, or
not yet pushed**. Without access to the source and its LICENSE, the licensing
status is **UNCLEAR** by definition.

## 3. Decision (per the Stage 1.1 rules)

The mandate states: *"GPL/AGPL/unclear → do NOT depend"* and *"Never block the
app on this dependency."* The status here is `unclear` (no source, no license
visible), therefore:

> **DECISION: DO NOT depend on `Music_Lyrics_Embedd` in any form — not as a
> package, not as a git dependency, not as vendored code.**
>
> Instead, Wavely ships its **own from-scratch LRC parser** at
> `lib/features/lyrics/domain/lrc_parser.dart` (MIT-owned, part of Wavely),
> with the full unit-test matrix required by Stage 1.1 (multi-timestamp lines,
> offset tags, BOM, CRLF, unicode, word-level `<mm:ss.xx>` tags, etc.).
>
> No code, algorithm, or asset from `Music_Lyrics_Embedd` is copied, so no
> attribution or `third_party/` entry is required at this time.

## 4. Consequence for the provider chain

The lyrics resolution chain for Stage 1.1 is:

1. `EmbeddedLyricsProvider` — SYLT/USLT extracted during library scan → `lyrics_cache`
2. ~~`MusicLyricsEmbeddProvider`~~ — **removed from the chain** (repo inaccessible)
3. `LrclibLyricsProvider` — public LRCLIB API (no key required), cached forever
4. `null` — empty state; the app never throws on lyrics

The chain position of a future `MusicLyricsEmbeddProvider` is preserved; if the
repository becomes public with a permissive license and clean deps, re-run this
inspection and slot the provider in at position 2 without UI changes.

## 5. Re-inspection checklist (for the owner, when the repo is public)

1. `git clone https://github.com/Dani-Devlop/Music_Lyrics_Embedd`
2. Record LICENSE (SPDX id) and dependency licenses.
3. If MIT/BSD/Apache/ISC **and** clean deps → implement `MusicLyricsEmbeddProvider`
   as a `LyricsProvider` implementation, insert into `LyricsRepository` chain,
   and extend the contract test suite to cover it.
4. If GPL/AGPL/heavy/abandoned → extract only the LRC parsing logic into
   `third_party/Music_Lyrics_Embedd/` with attribution + original license
   header, and adapt `lrc_parser.dart` accordingly.
5. Update this report with the new findings and decision.

---

## Addendum — Stage 1.1 completion session

Re-checked during the Stage 1.1 completion pass: the repository remains
**HTTP 404** (clone and raw fetch both fail; not publicly accessible). The
decision above therefore **holds and is final for Stage 1.1**:

- No dependency on `Music_Lyrics_Embedd` in any form.
- LRC parsing is implemented **from scratch** in
  `lib/features/lyrics/domain/lrc_parser.dart` (18 unit tests, all authored).
- Provider chain shipped as: embedded (scan-extracted SYLT/USLT) → LRCLIB → null.
- The `MusicLyricsEmbeddProvider` chain slot (position 2) is intentionally
  reserved; re-run the §5 checklist if/when the repository becomes public.
