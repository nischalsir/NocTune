// Entrance animations for the selected navigation icon.
import 'package:flutter/material.dart';

/// How a navigation icon arrives when its destination becomes selected.
enum NavIconMotion { bounce, slide, spin }

/// Plays [motion] once, when the icon is first shown as selected. With
/// reduced motion on, the icon simply appears.
class AnimatedNavIcon extends StatefulWidget {
  const AnimatedNavIcon({super.key, required this.motion, required this.child});

  final NavIconMotion motion;
  final Widget child;

  @override
  State<AnimatedNavIcon> createState() => _AnimatedNavIconState();
}

class _AnimatedNavIconState extends State<AnimatedNavIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: switch (widget.motion) {
      NavIconMotion.bounce => const Duration(milliseconds: 360),
      NavIconMotion.slide => const Duration(milliseconds: 300),
      NavIconMotion.spin => const Duration(milliseconds: 460),
    },
  )..forward();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final settle = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    return switch (widget.motion) {
      // Pops up from slightly small, overshooting a touch.
      NavIconMotion.bounce => ScaleTransition(
        scale: Tween<double>(begin: 0.55, end: 1).animate(settle),
        child: widget.child,
      ),
      // Rises into place as it fades in.
      NavIconMotion.slide => FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(settle),
          child: widget.child,
        ),
      ),
      // A third of a turn, as a cog would.
      NavIconMotion.spin => RotationTransition(
        turns: Tween<double>(begin: -1 / 3, end: 0).animate(settle),
        child: widget.child,
      ),
    };
  }
}
