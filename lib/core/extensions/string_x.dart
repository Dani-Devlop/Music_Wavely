const String _untitled = 'untitled';
const int _maxSanitizedLength = 120;

/// Matches control characters (including DEL) that break display and files.
final RegExp _controlCharsPattern = RegExp(r'[\x00-\x1F\x7F]');

/// Matches characters that are illegal in file names on common platforms.
final RegExp _illegalFilenameCharsPattern = RegExp(r'[<>:"/\\|?*]');

final RegExp _whitespacePattern = RegExp(r'\s+');

/// Helpers for turning arbitrary metadata (track titles, playlist names, ...)
/// into safe display strings and file names.
extension StringX on String {
  /// True when the string is empty or only whitespace.
  bool get isBlank => trim().isEmpty;

  /// True when the string contains at least one non-whitespace character.
  bool get isNotBlank => !isBlank;

  /// Strips control characters and file-name illegal characters, collapses
  /// whitespace runs into single spaces, trims, caps the result at 120
  /// characters and falls back to `untitled` when nothing remains.
  String get sanitized {
    if (isBlank) {
      return _untitled;
    }
    final withoutControlChars = replaceAll(_controlCharsPattern, ' ');
    final withoutIllegalChars =
        withoutControlChars.replaceAll(_illegalFilenameCharsPattern, '');
    final collapsed = withoutIllegalChars
        .replaceAll(_whitespacePattern, ' ')
        .trim();
    final capped = collapsed.length > _maxSanitizedLength
        ? collapsed.substring(0, _maxSanitizedLength)
        : collapsed;
    if (capped.isEmpty) {
      return _untitled;
    }
    return capped;
  }
}
