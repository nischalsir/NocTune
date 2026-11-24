import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';
import 'frosted.dart';

/// A round glass button face with an icon. Pass [blurBackdrop] where content
/// scrolls underneath it, so what is behind is frosted rather than showing
/// through.
class GlassCircle extends StatelessWidget {
  const GlassCircle(
    IconData this.icon, {
    super.key,
    this.size = 44,
    this.blurBackdrop = false,
  }) : glyph = null;

  /// The same face with a drawing of its own in place of an icon, such as
  /// one that moves.
  const GlassCircle.glyph(
    Widget this.glyph, {
    super.key,
    this.size = 44,
    this.blurBackdrop = false,
  }) : icon = null;

  final IconData? icon;
  final Widget? glyph;
  final double size;
  final bool blurBackdrop;

  @override
  Widget build(BuildContext context) {
    return Frosted(
      blurBackdrop: blurBackdrop,
      child: SizedBox.square(
        dimension: size,
        child:
            glyph ??
            Icon(icon, size: size * 0.46, color: context.noc.textPrimary),
      ),
    );
  }
}
