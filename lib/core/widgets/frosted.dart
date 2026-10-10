import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';

/// The frosted-glass finish used on buttons: a fully rounded shape with a
/// soft top-lit translucent fill and a hairline rim.
///
/// By default it only paints the finish, which is all that is needed on
/// surfaces that are already blurred (the player, the glass bars). Pass
/// [blurBackdrop] where it sits directly over artwork or scrolling content,
/// so what is behind it is genuinely frosted. That costs a blur pass, so it
/// is reserved for the few buttons that need it.
class Frosted extends StatelessWidget {
  const Frosted({
    super.key,
    required this.child,
    this.tint,
    this.blurBackdrop = false,
  });

  final Widget child;

  /// Colours the glass, for a button that carries the accent.
  final Color? tint;
  final bool blurBackdrop;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final highContrast = MediaQuery.highContrastOf(context);
    final tint = this.tint;

    final ShapeDecoration decoration;
    if (highContrast) {
      decoration = ShapeDecoration(
        color: tint ?? palette.glassSolid,
        shape: StadiumBorder(side: BorderSide(color: palette.textSecondary)),
      );
    } else {
      // Brighter at the top edge, as if lit from above.
      final base = tint?.withValues(alpha: 0.78) ?? palette.glass;
      decoration = ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(base, Colors.white, 0.16)!, base],
        ),
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: tint == null ? 0.16 : 0.30),
          ),
        ),
      );
    }

    final surface = DecoratedBox(decoration: decoration, child: child);
    if (!blurBackdrop || highContrast) return surface;
    return ClipPath(
      clipper: const ShapeBorderClipper(shape: StadiumBorder()),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: surface,
      ),
    );
  }
}
