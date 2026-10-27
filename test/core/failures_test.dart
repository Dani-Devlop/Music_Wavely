/// Authored, awaiting local run (Task 2-a).
///
/// Tests for `lib/core/errors/failures.dart` — the sealed freezed failure
/// hierarchy (`Failure.network/storage/permission/parsing/unknown`) with
/// `message` + optional `cause` fields, value equality, copyWith and
/// exhaustive-switch ergonomics.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/failures.dart';

void main() {
  group('Failure factories', () {
    test('network builds a NetworkFailure with its fields', () {
      final cause = Exception('socket closed');
      final failure = Failure.network(message: 'offline', cause: cause);
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, 'offline');
      expect(failure.cause, same(cause));
    });

    test('storage builds a StorageFailure', () {
      final failure = Failure.storage(message: 'disk full');
      expect(failure, isA<StorageFailure>());
      expect(failure.message, 'disk full');
    });

    test('permission builds a PermissionFailure', () {
      final failure = Failure.permission(message: 'denied');
      expect(failure, isA<PermissionFailure>());
      expect(failure.message, 'denied');
    });

    test('parsing builds a ParsingFailure', () {
      final failure = Failure.parsing(message: 'bad lrc');
      expect(failure, isA<ParsingFailure>());
      expect(failure.message, 'bad lrc');
    });

    test('unknown builds an UnknownFailure', () {
      final failure = Failure.unknown(message: '???');
      expect(failure, isA<UnknownFailure>());
      expect(failure.message, '???');
    });

    test('cause is optional and defaults to null', () {
      expect(Failure.unknown(message: 'm').cause, isNull);
    });
  });

  group('Failure equality (freezed value semantics)', () {
    test('same kind + same fields are equal', () {
      final a = Failure.network(message: 'm', cause: 'c');
      final b = Failure.network(message: 'm', cause: 'c');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different messages are not equal', () {
      expect(
        Failure.network(message: 'a'),
        isNot(equals(Failure.network(message: 'b'))),
      );
    });

    test('different causes are not equal', () {
      expect(
        Failure.network(message: 'm', cause: 1),
        isNot(equals(Failure.network(message: 'm', cause: 2))),
      );
    });

    test('different kinds are never equal, even with equal fields', () {
      expect(
        Failure.network(message: 'same'),
        isNot(equals(Failure.storage(message: 'same'))),
      );
      expect(
        Failure.permission(message: 'same'),
        isNot(equals(Failure.parsing(message: 'same'))),
      );
      expect(
        Failure.parsing(message: 'same'),
        isNot(equals(Failure.unknown(message: 'same'))),
      );
    });
  });

  group('Failure copyWith', () {
    test('copies replace provided fields and keep the rest', () {
      final original = Failure.storage(message: 'original') as StorageFailure;
      final copied = original.copyWith(message: 'updated');
      expect(copied, isA<StorageFailure>());
      expect(copied.message, 'updated');
      expect(copied.cause, isNull);

      final cause = StateError('root');
      final withCause = original.copyWith(cause: cause);
      expect(withCause.message, 'original');
      expect(withCause.cause, same(cause));
    });

    test('copyWith with no arguments is equal to the original', () {
      final original = Failure.parsing(message: 'm', cause: 7) as ParsingFailure;
      expect(original.copyWith(), equals(original));
    });
  });

  group('Failure exhaustive switch', () {
    test('every kind dispatches to its own branch', () {
      String label(Failure failure) => switch (failure) {
            NetworkFailure() => 'network',
            StorageFailure() => 'storage',
            PermissionFailure() => 'permission',
            ParsingFailure() => 'parsing',
            UnknownFailure() => 'unknown',
          };

      expect(label(Failure.network(message: 'x')), 'network');
      expect(label(Failure.storage(message: 'x')), 'storage');
      expect(label(Failure.permission(message: 'x')), 'permission');
      expect(label(Failure.parsing(message: 'x')), 'parsing');
      expect(label(Failure.unknown(message: 'x')), 'unknown');
    });
  });
}
