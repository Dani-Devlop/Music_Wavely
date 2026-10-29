/// File-name sanitizer for the download manager (Stage 2.1 Section 9).
///
/// Rules (Windows-safe by default, per spec):
/// - illegal characters `<>:"/\|?*` become `_`;
/// - ASCII control characters (0x00–0x1F, 0x7F) become `_`;
/// - trailing dots and spaces are trimmed (Windows ignores them);
/// - reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9) get a
///   `_` suffix, case-insensitively;
/// - the result is clamped to [maxLength] (default 200 — comfortably below
///   the 260-char Windows MAX_PATH budget so the surrounding folder
///   template still fits);
/// - unicode is preserved (no transliteration) — only the illegal set is
///   replaced;
/// - an empty result falls back to `untitled`.
library;

/// Windows-reserved device names (case-insensitive, with or without
/// extension).
const Set<String> _reserved = <String>{
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Characters Windows forbids in file names.
final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]');

/// Sanitises a single file or folder name [name].
String sanitizeFilename(String name, {int maxLength = 200}) {
  var out = name.replaceAll(_illegal, '_');
  // Trim trailing dots/spaces (Windows) and leading spaces.
  out = out.trim().replaceFirst(RegExp(r'^\s+'), '');
  while (out.endsWith('.') || out.endsWith(' ')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.isEmpty) {
    return 'untitled';
  }
  // Reserved device names: CON, CON.mp3, con.MP3 ...
  // The `_` suffix goes on the STEM only (COM9.txt -> COM9_.txt), so the
  // extension stays intact while the reserved base name is escaped.
  final int firstDot = out.indexOf('.');
  final String stem = firstDot == -1 ? out : out.substring(0, firstDot);
  if (_reserved.contains(stem.toUpperCase())) {
    out = firstDot == -1 ? '${out}_' : '${stem}_${out.substring(firstDot)}';
  }
  if (out.length > maxLength) {
    // Preserve the extension when the cut would eat it.
    final int dot = out.lastIndexOf('.');
    if (dot > maxLength - 5) {
      final String ext = out.substring(dot + 1);
      final String stem = out.substring(0, maxLength - ext.length - 1);
      out = '$stem.$ext';
    } else {
      out = out.substring(0, maxLength);
    }
  }
  return out;
}

/// Builds a safe two-part file name `"<title>.<ext>"` from a track title
/// and a (possibly dotless) format/extension hint.
///
/// The extension is sanitized (illegal characters escaped) but its full
/// spelling is preserved — truncating an extension would corrupt the
/// format association — so the default 200-char bound applies instead of
/// a short clamp.
String buildTrackFilename(String title, String format) {
  final String ext = format.isEmpty ? 'mp3' : sanitizeFilename(format);
  return '${sanitizeFilename(title)}.$ext';
}
