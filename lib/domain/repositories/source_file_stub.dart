/// Compile-only web stub standing in for `dart:io` [File] inside
/// [SourceProvider] signatures. Never functional: downloading is an
/// io-platform capability and Stage 1.1 ships no SourceProvider at all.
class File {
  const File();

  /// Intentionally unsupported on web — mirrors dart:io's absence.
  Never get unsupported => throw UnsupportedError(
        'File operations require an IO platform (desktop or mobile).',
      );
}
