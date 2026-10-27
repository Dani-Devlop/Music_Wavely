import 'package:flutter/material.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';

/// Small icon identifying the source a track came from.
///
/// Mapping: `local` → library, self-hosted servers (subsonic/navidrome) →
/// server rack, `jamendo` → globe, `archive` → institution, metadata-only
/// catalogs (spotify/deezer/apple) → music note, anything else → generic
/// audio icon.
class SourceBadge extends StatelessWidget {
  const SourceBadge({
    required this.sourceId,
    this.size = 14,
    this.withTooltip = true,
    super.key,
  });

  final String sourceId;

  /// Icon glyph size in logical pixels.
  final double size;
  final bool withTooltip;

  bool get _isMetadataOnly {
    final id = sourceId.toLowerCase();
    return id == 'spotify' || id == 'deezer' || id == 'apple';
  }

  IconData get _icon {
    final id = sourceId.toLowerCase();
    if (id == 'local') {
      return Icons.library_music_rounded;
    }
    if (id.contains('subsonic') || id.contains('navidrome')) {
      return Icons.dns_rounded;
    }
    if (id == 'jamendo') {
      return Icons.public_rounded;
    }
    if (id == 'archive') {
      return Icons.account_balance_rounded;
    }
    if (_isMetadataOnly) {
      return Icons.music_note_rounded;
    }
    return Icons.audiotrack_rounded;
  }

  String get _tooltip =>
      _isMetadataOnly ? 'Metadata only' : 'Source: $sourceId';

  @override
  Widget build(BuildContext context) {
    final colors = context.wavelyColors;
    final icon = Icon(_icon, size: size, color: colors.textTertiary);
    if (!withTooltip) {
      return icon;
    }
    return Tooltip(message: _tooltip, child: icon);
  }
}
