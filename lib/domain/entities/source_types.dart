import 'package:freezed_annotation/freezed_annotation.dart';

part 'source_types.freezed.dart';

/// Quality tiers a source can offer when resolving or downloading streams.
enum AudioQuality { low, medium, high, lossless }

/// Kinds of audio sources supported by Wavely.
enum SourceKind { local, selfHosted, freeCatalog, metadataOnly }

/// A resolved, playable stream with optional auth headers and expiry.
@freezed
abstract class StreamUrl with _$StreamUrl {
  const factory StreamUrl({
    required String url,
    Map<String, String>? headers,
    DateTime? expiresAt,
  }) = _StreamUrl;
}
