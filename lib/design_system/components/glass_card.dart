import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavely/design_system/themes/semantic_extension.dart';
import 'package:wavely/design_system/tokens/blur.dart';
import 'package:wavely/design_system/tokens/radii.dart';
import 'package:wavely/design_system/tokens/shadows.dart';
// Layering bend (Task B/E1, accepted): the design system reads the canonical
// settings flag through the settings feature's provider instead of the legacy
// themeSettingsProvider. A shared core-level provider module would be the
// cleaner home — revisit if the design system grows more settings reads.
import 'package:wavely/features/settings/data/settings_provider.dart';

/// Frosted-glass surface card used across the app.
///
/// By default the card renders a real backdrop blur ([BackdropFilter]) over a
/// translucent surface tint. When the user enables "reduce transparency" in
/// settings (read from the canonical AppSettings via
/// reduceTransparencyProvider), it falls back to a fully opaque surface (the
/// given [color], else `elevated`, alpha-blended over `bgBase`) with the same
/// radius, border and shadow.
///
/// NEVER use inside ListView items (max 3 BackdropFilters per screen — see
/// AppConstants.maxBackdropFiltersPerScreen). Reserve this card for hero
/// surfaces: mini player, headers, dialogs, empty-state chrome.
class GlassCard extends ConsumerWidget {
  const GlassCard({
    required this.child,
    this.blurSigma,
    this.borderRadius,
    this.padding,
    this.color,
    this.elevated = false,
    this.onTap,
    super.key,
  });

  final Widget child;
  final double? blurSigma;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final bool elevated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.wavelyColors;
    final translucent = !ref.watch(reduceTransparencyProvider);
    final radius = borderRadius ?? AppRadii.bLg;
    final sigma =
        blurSigma ?? (elevated ? WavelyBlur.elevated : WavelyBlur.surface);

    Widget content = ClipRRect(
      borderRadius: radius,
      child: translucent
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: _glass(context, radius),
            )
          : _solid(context, radius),
    );

    if (elevated) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: colors.isDark ? WavelyShadows.dark : WavelyShadows.light,
        ),
        child: content,
      );
    }

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _glass(BuildContext context, BorderRadius radius) {
    final colors = context.wavelyColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: color == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[colors.surface, colors.elevated],
              )
            : null,
        color: color,
        border: Border.all(color: colors.borderGlass),
      ),
      child: child,
    );
  }

  Widget _solid(BuildContext context, BorderRadius radius) {
    final colors = context.wavelyColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Color.alphaBlend(color ?? colors.elevated, colors.bgBase),
        border: Border.all(color: colors.borderGlass),
      ),
      child: child,
    );
  }
}
