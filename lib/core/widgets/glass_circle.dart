import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';
import 'frosted.dart';

/// A round glass button face with an icon. Pass [blurBackdrop] where content
/// scrolls underneath it, so what is behind is frosted rather than showing
/// through.
class GlassCircle extends StatelessWidget {
  const GlassCircle(
    this.icon, {
    super.key,
    this.size = 44,
    this.blurBackdrop = false,
  });

  final IconData icon;
  final double size;
  final bool blurBackdrop;

  @override
  Widget build(BuildContext context) {
    return Frosted(
      blurBackdrop: blurBackdrop,
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * 0.46, color: context.noc.textPrimary),
      ),
    );
  }
}
