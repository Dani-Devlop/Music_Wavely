import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:wavely/core/errors/failures.dart';

part 'result.freezed.dart';

/// Either a [Success] value or an [Err] failure.
///
/// Prefer [fold] / pattern matching over `is` checks so that exhaustiveness
/// stays guaranteed by the compiler.
///
/// Freezed's generated `map`/`when` helpers are disabled so the hand-written
/// [map] (value-transforming) is the single unambiguous `map` on this type.
@Freezed(
  map: FreezedMapOptions.none,
  when: FreezedWhenOptions.none,
)
sealed class Result<T> with _$Result<T> {
  const factory Result.success(T value) = Success<T>;

  const factory Result.err(Failure failure) = Err<T>;

  const Result._();

  bool get isSuccess => this is Success<T>;

  bool get isErr => !isSuccess;

  R fold<R>({
    required R Function(Failure failure) onErr,
    required R Function(T value) onSuccess,
  }) =>
      switch (this) {
        Success<T>(:final value) => onSuccess(value),
        Err<T>(:final failure) => onErr(failure),
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success<T>(:final value) => Result<R>.success(transform(value)),
        Err<T>(:final failure) => Result<R>.err(failure),
      };

  T getOrElse(T Function(Failure failure) orElse) => switch (this) {
        Success<T>(:final value) => value,
        Err<T>(:final failure) => orElse(failure),
      };

  Future<Result<R>> flatMap<R>(
    Future<Result<R>> Function(T value) transform,
  ) async {
    switch (this) {
      case final Success<T> success:
        return await transform(success.value);
      case final Err<T> err:
        return Result<R>.err(err.failure);
    }
  }
}
