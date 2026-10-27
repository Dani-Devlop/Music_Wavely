import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';

/// Local user profile (privacy-first: stored on device only).
@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    String? displayName,
    String? avatarUrl,
    required DateTime createdAt,
  }) = _UserProfile;
}
