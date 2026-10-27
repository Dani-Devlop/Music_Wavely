/// Authored, awaiting local run (Task 2-a).
///
/// Contract tests for `lib/core/errors/result.dart` — the sealed
/// `Result<T>` union (`Success<T>` / `Err<T>`) with its hand-written
/// [Result.fold], [Result.map], [Result.getOrElse] and [Result.flatMap]
/// members (freezed's generated map/when are disabled on purpose, so the
/// value-transforming [Result.map] is the only `map`).

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/errors/failures.dart';
import 'package:wavely/core/errors/result.dart';

void main() {
  group('Result status flags', () {
    test('Success reports isSuccess true and isErr false', () {
      final result = Result<int>.success(1);
      expect(result.isSuccess, isTrue);
      expect(result.isErr, isFalse);
    });

    test('Err reports isSuccess false and isErr true', () {
      final result = Result<int>.err(Failure.unknown(message: 'boom'));
      expect(result.isSuccess, isFalse);
      expect(result.isErr, isTrue);
    });
  });

  group('Result.fold', () {
    test('runs onSuccess for Success and returns its value', () {
      final result = Result<int>.success(7);
      final folded = result.fold(
        onErr: (failure) => -1,
        onSuccess: (value) => value + 1,
      );
      expect(folded, 8);
    });

    test('runs onErr for Err and returns its value', () {
      final result = Result<int>.err(Failure.parsing(message: 'bad'));
      final folded = result.fold(
        onErr: (failure) => failure.message.length,
        onSuccess: (value) => value,
      );
      expect(folded, 3); // 'bad'.length
    });

    test('fold may return a different type than the payload', () {
      const result = Result<String>.success('ok');
      final length = result.fold(
        onErr: (_) => 0,
        onSuccess: (value) => value.length,
      );
      expect(length, 2);
    });
  });

  group('Result.map', () {
    test('transforms a Success value', () {
      final mapped = Result<int>.success(2).map<String>((value) => '$value!');
      expect(mapped.isSuccess, isTrue);
      expect((mapped as Success<String>).value, '2!');
    });

    test('passes the SAME failure through untouched', () {
      final failure = Failure.storage(message: 'disk full');
      final mapped = Result<int>.err(failure).map<String>((_) => 'unused');
      expect(mapped.isErr, isTrue);
      expect((mapped as Err<String>).failure, same(failure));
    });
  });

  group('Result.getOrElse', () {
    test('returns the value on Success', () {
      final value = Result<int>.success(5).getOrElse((_) => 0);
      expect(value, 5);
    });

    test('returns the orElse fallback (with the failure) on Err', () {
      final seen = <Failure>[];
      final value = Result<int>.err(Failure.network(message: 'offline'))
          .getOrElse((failure) {
        seen.add(failure);
        return 42;
      });
      expect(value, 42);
      expect(seen, hasLength(1));
      expect(seen.single, isA<NetworkFailure>());
    });
  });

  group('Result.flatMap', () {
    test('chains Success into a new Result', () async {
      final chained = await Result<int>.success(2).flatMap<String>(
            (value) async => Result<String>.success('v$value'),
          );
      expect(chained.isSuccess, isTrue);
      expect((chained as Success<String>).value, 'v2');
    });

    test('Success may chain into an Err', () async {
      final chained = await Result<int>.success(2).flatMap<String>(
            (_) async => Result<String>.err(Failure.permission(message: 'no')),
          );
      expect(chained.isErr, isTrue);
      expect((chained as Err<String>).failure, isA<PermissionFailure>());
    });

    test('Err short-circuits without invoking the transform', () async {
      final failure = Failure.unknown(message: 'short-circuit');
      var called = false;
      final chained = await Result<int>.err(failure).flatMap<String>(
            (_) async {
              called = true;
              return Result<String>.success('unreachable');
            },
          );
      expect(called, isFalse);
      expect(chained.isErr, isTrue);
      expect((chained as Err<String>).failure, same(failure));
    });
  });

  group('Result equality (freezed value semantics)', () {
    test('Success values compare by payload', () {
      expect(Result<int>.success(1), equals(Result<int>.success(1)));
      expect(Result<int>.success(1), isNot(equals(Result<int>.success(2))));
    });

    test('Err values compare by failure', () {
      expect(
        Result<int>.err(Failure.network(message: 'm')),
        equals(Result<int>.err(Failure.network(message: 'm'))),
      );
      expect(
        Result<int>.err(Failure.network(message: 'm')),
        isNot(equals(Result<int>.err(Failure.network(message: 'other')))),
      );
    });

    test('Success and Err with equal payloads are different branches', () {
      expect(
        Result<int>.success(1),
        isNot(equals(Result<int>.err(Failure.network(message: '1')))),
      );
    });

    test('hashCode agrees with equality', () {
      expect(
        Result<int>.success(3).hashCode,
        equals(Result<int>.success(3).hashCode),
      );
    });
  });

  group('Result sealed switch', () {
    test('pattern matching exposes value / failure fields', () {
      final Result<int> success = Result<int>.success(9);
      final Result<int> err = Result<int>.err(Failure.parsing(message: 'x'));

      expect(
        switch (success) {
          Success<int>(:final value) => value,
          Err<int>() => -1,
        },
        9,
      );
      expect(
        switch (err) {
          Success<int>() => 'value',
          Err<int>(:final failure) => failure.message,
        },
        'x',
      );
    });
  });
}
