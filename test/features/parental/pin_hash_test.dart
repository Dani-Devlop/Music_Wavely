/// Authored, awaiting local run (Task 2-f / Stage 3 audit).
///
/// [hashPin] / [verifyPin] / [isValidPin] contract after the Stage 3
/// hardened-v3 upgrade: `p3$<salt>$<hash>` (iterated sha256) output that
/// verifies, fresh random salt per call, legacy `p2$` salted hashes and
/// plain-sha256 v1 hashes still accepted, wrong pins rejected, and the
/// 4-8 digit shape validation boundaries.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';

/// Stage 3 audit (SEC-11): the v3 iteration count is a private constant —
/// tests recompute the expected digest with the same schedule inline.
const int _kV3Rounds = 10000;

String _iteratedHash(String seed) {
  var digest = Uint8List.fromList(utf8.encode(seed));
  for (var i = 0; i < _kV3Rounds; i++) {
    digest = Uint8List.fromList(sha256.convert(digest).bytes);
  }
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  group('hashPin (v3 hardened)', () {
    test('produces a p3\$-prefixed iterated hash that verifies', () {
      final hash = hashPin('4821');
      expect(hash.startsWith('p3\$'), isTrue);
      final body = hash.substring(3);
      // 16 salt bytes (32 hex chars) + sha256 digest (64 hex chars).
      expect(body.length, 96);
      final saltHex = body.substring(0, 32);
      final digest = body.substring(32);
      final expected = _iteratedHash('$saltHex:4821');
      expect(digest, expected);
      expect(verifyPin('4821', hash), isTrue);
    });

    test('every call uses a fresh random salt', () {
      final a = hashPin('1234');
      final b = hashPin('1234');
      expect(a, isNot(b));
      // Different salts → different digests, yet both verify.
      expect(verifyPin('1234', a), isTrue);
      expect(verifyPin('1234', b), isTrue);
    });

    test('wrong pins are rejected against the v3 hash', () {
      final hash = hashPin('2468');
      expect(verifyPin('2467', hash), isFalse);
      expect(verifyPin('24680', hash), isFalse);
      expect(verifyPin('', hash), isFalse);
    });

    test('truncated payloads (missing digest) never verify', () {
      expect(verifyPin('1234', 'p3\$abcdef'), isFalse);
      expect(verifyPin('1234', 'p2\$abcdef'), isFalse);
    });
  });

  group('verifyPin (legacy migration)', () {
    test('still accepts p2\$ salted hashes (pre-Stage-3 profiles)', () {
      // Recreate the exact v2 format: sha256('<saltHex>:<pin>'), one round.
      const saltHex = 'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4';
      final v2Digest =
          sha256.convert(utf8.encode('$saltHex:7777')).toString();
      final v2 = 'p2\$$saltHex$v2Digest';
      expect(verifyPin('7777', v2), isTrue);
      expect(verifyPin('7776', v2), isFalse);
    });

    test('still accepts plain sha256 hex hashes (v1)', () {
      final legacy = sha256.convert(utf8.encode('9999')).toString();
      expect(verifyPin('9999', legacy), isTrue);
      expect(verifyPin('9998', legacy), isFalse);
    });

    test('rejects garbage hashes without throwing', () {
      expect(verifyPin('1234', ''), isFalse);
      expect(verifyPin('1234', 'zz-not-even-hex'), isFalse);
    });
  });

  group('isValidPin shape boundaries', () {
    test('accepts 4 through 8 digits', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('0000'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('12345678'), isTrue);
    });

    test('rejects 3 digits, 9 digits, letters and empties', () {
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('123456789'), isFalse);
      expect(isValidPin('abcd'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin('1 34'), isFalse);
      expect(isValidPin(''), isFalse);
    });
  });
}
