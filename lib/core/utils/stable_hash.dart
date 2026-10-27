import 'dart:convert';

/// FNV-1a 64-bit offset basis.
const int _fnvOffsetBasis = 0xcbf29ce484222325;

/// FNV-1a 64-bit prime.
const int _fnvPrime = 0x100000001b3;

/// Separator used by [hashList] so that joined element boundaries cannot be
/// confused with content.
const String _listSeparator = '\x1f';

/// Computes a deterministic FNV-1a 64-bit hash of [object] and returns it as
/// a base-36 string.
///
/// Used for stable content keys (e.g. `sourceTrackId` for scanned files) that
/// must survive restarts without a crypto dependency. The implementation runs
/// on 64-bit two's-complement ints, so results are stable on VM/desktop and
/// mobile; web builds use JS numbers and are only guaranteed stable within a
/// single session (the scanner is disabled on web anyway).
///
/// Any object is accepted; its [Object.toString] form is UTF-8 encoded before
/// hashing, so callers that need unambiguous keys should embed enough context
/// themselves (the scanner hashes `'$path:$fileSize:$mtimeMs'`).
String stableHash(Object object) {
  final bytes = utf8.encode(object.toString());
  var hash = _fnvOffsetBasis;
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = hash * _fnvPrime;
  }
  return hash.toRadixString(36);
}

/// Hashes [items] by joining their string forms with an unambiguous control
/// separator before hashing, so `['a', 'bc']` differs from `['ab', 'c']`.
String hashList(List<Object> items) => stableHash(items.join(_listSeparator));
