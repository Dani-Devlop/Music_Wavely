import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PIN hashing helper for the parental-control gate.
///
/// v2 (salted): each hash is stored as `p2$<saltHex>$<hashHex>` where
/// `hashHex = sha256('<saltHex>:<pin>')` and `saltHex` is 16 random bytes
/// hex generated per call by [Random.secure]. A 4-digit PIN is still a
/// small keyspace, but the per-PIN salt means an attacker must brute-force
/// every profile separately and cannot match PINs across profiles via
/// rainbow tables. A real KDF (bcrypt/argon2) remains the security-pass
/// follow-up if the threat model ever grows beyond on-device storage.
///
/// Migration: [verifyPin] still accepts v1 hashes (plain `sha256(pin)`
/// hex, exactly 64 chars, no `p2$` prefix) so profiles created before the
/// upgrade keep working; re-save the PIN to upgrade the stored hash.

/// Salt length in bytes (16 bytes = 128 bits of randomness).
const int _saltBytes = 16;

/// Version prefix of the salted hash format.
const String _v2Prefix = 'p2\$';

/// Hashes [pin] with a fresh random salt (`p2$<salt>$<hash>`).
///
/// Callers persist the returned string verbatim; verification goes through
/// [verifyPin], never by re-hashing and comparing.
String hashPin(String pin) {
  final rnd = Random.secure();
  final salt = List<int>.generate(_saltBytes, (_) => rnd.nextInt(256));
  final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final digest =
      sha256.convert(utf8.encode('$saltHex:$pin')).toString();
  return '$_v2Prefix$saltHex$digest';
}

/// Checks [pin] against a stored [hash].
///
/// Accepts both v2 salted hashes (see [hashPin]) and legacy v1 plain
/// `sha256(pin)` hex so pre-existing profiles still unlock. Comparison is
/// constant-length (both sides hex of fixed size); timing side channels are
/// irrelevant here because the hash never leaves the device.
bool verifyPin(String pin, String hash) {
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
