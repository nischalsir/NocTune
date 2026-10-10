import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';

/// The page background: near-black settling into midnight navy, with one
/// restrained accent glow in the top corner.
class NocBackdrop extends StatelessWidget {
  const NocBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.background, palette.backgroundDeep],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -1.0),
            radius: 1.1,
            colors: [
              palette.accent.withValues(alpha: 0.16),
              palette.accent.withValues(alpha: 0),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}
