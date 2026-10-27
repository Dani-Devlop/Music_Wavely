/// Authored, awaiting local run (Task 2-f).
///
/// [hashPin] / [verifyPin] / [isValidPin] contract after the salted-v2
/// upgrade: `p2$<salt>$<hash>` output that verifies, fresh random salt per
/// call, legacy plain-sha256 hashes still accepted, wrong pins rejected,
/// and the 4-8 digit shape validation boundaries.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/parental/data/pin_hash.dart';

void main() {
  group('hashPin (v2 salted)', () {
    test('produces a p2$-prefixed salted hash that verifies', () {
      final hash = hashPin('4821');
      expect(hash.startsWith('p2\$'), isTrue);
      final body = hash.substring(3);
      // 16 salt bytes (32 hex chars) + sha256 digest (64 hex chars).
      expect(body.length, 96);
      final saltHex = body.substring(0, 32);
      final digest = body.substring(32);
      final expected =
          sha256.convert(utf8.encode('$saltHex:4821')).toString();
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

    test('wrong pins are rejected against the v2 hash', () {
      final hash = hashPin('2468');
      expect(verifyPin('2467', hash), isFalse);
      expect(verifyPin('24680', hash), isFalse);
      expect(verifyPin('', hash), isFalse);
    });

    test('truncated payloads (missing digest) never verify', () {
      expect(verifyPin('1234', 'p2\$abcdef'), isFalse);
    });
  });

  group('verifyPin (legacy v1 migration)', () {
    test('still accepts plain sha256 hex hashes', () {
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
