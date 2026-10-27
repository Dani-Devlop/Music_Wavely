import 'package:flutter/material.dart';
import 'package:wavely/design_system/components/track_tile.dart';
import 'package:wavely/design_system/components/wavely_cover.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/spacing.dart';
import 'package:wavely/design_system/tokens/typography.dart';

/// Square album cover with title / artist caption underneath.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    required this.title,
    required this.artist,
    this.coverPath,
    this.onTap,
    this.width = 160,
    super.key,
  });

  final String title;
  final String artist;
  final String? coverPath;
  final VoidCallback? onTap;

  /// Fixed card width in logical pixels; the cover is square (aspect 1:1).
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.bMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: AppRadii.bMd,
                child: _cover(),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              title,
              style: WavelyTypography.body14Medium(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              artist,
              style: WavelyTypography.caption12(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover() {
    final provider = wavelyCoverProvider(coverPath);
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => WavelyCoverFallback(label: title),
      );
    }
    return WavelyCoverFallback(label: title);
  }
}
