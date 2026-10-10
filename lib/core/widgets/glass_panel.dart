import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';

/// A translucent surface with a hairline border, used for cards and floating
/// chrome. Falls back to a solid fill when the user has raised contrast.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.blur = 24,
    this.chrome = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Use the denser fill meant for floating bars. They sit over whatever
  /// scrolls beneath, so a light tint alone would not keep labels readable.
  final bool chrome;

  /// Backdrop blur sigma. Pass 0 for panels inside long scrolling lists,
  /// where a blur per item is too expensive.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final highContrast = MediaQuery.highContrastOf(context);
    final borderRadius = BorderRadius.circular(radius);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: highContrast
            ? palette.glassSolid
            : (chrome ? palette.glassChrome : palette.glass),
        borderRadius: borderRadius,
        border: Border.all(
          color: highContrast ? palette.textSecondary : palette.glassBorder,
        ),
      ),
      // Gives buttons and tiles inside the panel a surface to draw their
      // press ripples on; otherwise they land beneath the panel's fill.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );

    if (highContrast || blur == 0) {
      return ClipRRect(borderRadius: borderRadius, child: surface);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: surface,
      ),
    );
  }
}
