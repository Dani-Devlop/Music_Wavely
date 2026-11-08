# Vendored SQLite amalgamation

This directory contains the SQLite amalgamation (`sqlite3.c`, `sqlite3.h`),
version **3.54.1**, downloaded from <https://sqlite.org/2026/sqlite-amalgamation-3540100.zip>.

## Why vendored?

The `sqlite3` Dart package's native-assets build hook downloads prebuilt
`libsqlite3` binaries from the `simolus3/sqlite3.dart` GitHub release by
default. CI runners intermittently received corrupted bytes for those
release-asset URLs (identical wrong SHA-256 for different assets →
`Bad state: Hash of downloaded file ...`), which broke the Android /
Windows / Linux builds in `verify.yml`, `e2e.yml` and `release.yml`.
Compiling from the vendored amalgamation removes the network dependency
entirely and makes the native build deterministic.

## Wiring

`pubspec.yaml` configures the hook accordingly:

```yaml
hooks:
  user_defines:
    sqlite3:
      source:
        default: source
      path: third_party/sqlite3/sqlite3.c
      additional_includes:
        - third_party/sqlite3/
```

The hook applies its default feature set, which includes
`SQLITE_ENABLE_FTS5` (required by Wavely's instant-search index),
`SQLITE_ENABLE_RTREE`, `SQLITE_ENABLE_MATH_FUNCTIONS` and other standard
options — see `lib/src/hook/compile/description.dart` in the `sqlite3`
package for the authoritative list.

SQLite is public domain — no license obligations are added by vendoring it.
