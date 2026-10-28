import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN hashing helper for the parental-control gate.
///
/// v3 (Stage 3 audit, SEC-11): each hash is stored as
/// `p3$<saltHex>$<hashHex>` where `hashHex` is sha256 iterated 10,000×
/// over `sha256('<saltHex>:<pin>')` and `saltHex` is 16 random bytes hex
/// generated per call by [Random.secure]. The iteration count turns an
/// exfiltrated 4-digit PIN from an instant table scan into real work while
/// staying a pure-Dart, dependency-free KDF.
///
/// Migration: [verifyPin] still accepts v2 salted hashes (`p2$`, single
/// round) and v1 plain `sha256(pin)` hex so profiles created before the
/// upgrades keep working; re-saving the PIN upgrades the stored hash.

/// Salt length in bytes (16 bytes = 128 bits of randomness).
const int _saltBytes = 16;

/// Iteration count of the v3 hardened format (see the library doc).
const int _v3Rounds = 10000;

/// Version prefix of the hardened hash format.
const String _v3Prefix = 'p3\$';

/// Version prefix of the salted (single-round) hash format.
const String _v2Prefix = 'p2\$';

/// Hashes [pin] with a fresh random salt (`p3$<salt>$<hash>`).
///
/// Callers persist the returned string verbatim; verification goes through
/// [verifyPin], never by re-hashing and comparing.
String hashPin(String pin) {
  final rnd = Random.secure();
  final salt = List<int>.generate(_saltBytes, (_) => rnd.nextInt(256));
  final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$_v3Prefix$saltHex${_iteratedHex('$saltHex:$pin')}';
}

/// Iterated-sha256 chain used by the v3 format.
String _iteratedHex(String seed) {
  var digest = utf8.encode(seed);
  for (var i = 0; i < _v3Rounds; i++) {
    digest = sha256.convert(digest).bytes;
  }
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Checks [pin] against a stored [hash].
///
/// Accepts both v2 salted hashes (see [hashPin]) and legacy v1 plain
/// `sha256(pin)` hex so pre-existing profiles still unlock. Comparison is
/// constant-length (both sides hex of fixed size); timing side channels are
/// irrelevant here because the hash never leaves the device.
bool verifyPin(String pin, String hash) {
  if (hash.startsWith(_v3Prefix)) {
    final body = hash.substring(_v3Prefix.length);
    if (body.length <= _saltBytes * 2) {
      return false; // missing digest part
    }
    final saltHex = body.substring(0, _saltBytes * 2);
    final expected = body.substring(_saltBytes * 2);
    final actual = _iteratedHex('$saltHex:$pin');
    return _fixedTimeEquals(actual, expected);
  }
  if (hash.startsWith(_v2Prefix)) {
    final body = hash.substring(_v2Prefix.length);
    if (body.length <= _saltBytes * 2) {
      return false; // missing digest part
    }
    final saltHex = body.substring(0, _saltBytes * 2);
    final expected = body.substring(_saltBytes * 2);
    final actual =
        sha256.convert(utf8.encode('$saltHex:$pin')).toString();
    return _fixedTimeEquals(actual, expected);
  }
  // Legacy v1: plain unsalted sha256 hex.
  return _fixedTimeEquals(sha256.convert(utf8.encode(pin)).toString(), hash);
}

/// Compares two hex digests without short-circuiting on the first
/// difference (defensive habit; both inputs are fixed-length here anyway).
bool _fixedTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Validates the shape of a PIN before hashing/verifying (4-8 digits).
bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);
