# Contributing to Wavely

Thanks for helping! Short rules to keep the project consistent.

## Ground rules

- **Legal sources only.** No DRM circumvention, no unofficial paid-service
  APIs (no librespot / spotdl / zotify equivalents), no scraping of paid
  catalog audio. PRs violating this are closed without review.
- **Additive-first.** Do not rewrite existing stage code unless fixing a
  verified bug; keep the stage ledgers (`docs/STAGE_*_REPORT.md`) honest.
- **Every feature ships with tests.** Tests carry the header comment
  `// authored, awaiting local run.` until the owner's verification pass
  has executed them.

## Commit conventions

- Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
- Scope when useful: `feat(news): category chips`.
- Subject ≤ 72 chars; body explains WHY, not WHAT.
- **No `Co-authored-by` trailers** — commits come from the
  `Dani-Devlop` identity only:
  ```
  user.name  = Dani-Devlop
  user.email = Dani-Devlop@users.noreply.github.com
  ```

## PR flow

1. Branch from `main`: `feat/stage-X.Y` or `fix/…`.
2. Run locally before opening:
   ```bash
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter analyze
   flutter test --coverage
   ```
3. Fill the PR description with scope + verification status (honest: what
   ran, what didn't).
4. Squash-merge with a conventional subject; delete the branch.
5. `main` must stay green-by-authorship: every PR documents its local-run
   status in the body so the ledger stays truthful.

## Code style

- `very_good_analysis` lints are law (`flutter analyze` clean or the PR
  states exactly which findings remain and why).
- Design-system tokens only (`context.wavelyColors`, `Spacing`,
  `WavelyTypography`, `AppRadii`) — no raw hex in widgets.
- BackdropFilter budget: max 3 per screen (`AppConstants`); prefer the
  solid `_SectionGroup` pattern.
- Providers: manual `Provider`/`StateNotifier` unless codegen is already
  established in that file; tests override at the provider seam.

## Docs

- New feature → new section in the stage report + limitations appended to
  `docs/KNOWN_LIMITATIONS_FINAL.md`.
- User-facing behavior changes → `CHANGELOG.md`.
