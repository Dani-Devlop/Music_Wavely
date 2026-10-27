import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';

/// Root of the typed failure hierarchy used by Result-returning APIs.
///
/// Exhaustively switch over [Failure] (Dart 3 sealed classes) instead of using
/// runtime type checks or string codes.
@freezed
sealed class Failure with _$Failure {
  const factory Failure.network({
    required String message,
    Object? cause,
  }) = NetworkFailure;

  const factory Failure.storage({
    required String message,
    Object? cause,
  }) = StorageFailure;

  const factory Failure.permission({
    required String message,
    Object? cause,
  }) = PermissionFailure;

  const factory Failure.parsing({
    required String message,
    Object? cause,
  }) = ParsingFailure;

  const factory Failure.unknown({
    required String message,
    Object? cause,
  }) = UnknownFailure;

  const Failure._();
}
