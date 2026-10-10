// Entrance animations for the selected navigation icon.
//
// Adapted from SpotiFLAC-Mobile (lib/screens/main_shell.dart),
// MIT licence, © 2026 zarzet.
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
      NavIconMotion.bounce => const Duration(milliseconds: 400),
      NavIconMotion.slide => const Duration(milliseconds: 350),
      NavIconMotion.spin => const Duration(milliseconds: 500),
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
    return switch (widget.motion) {
      NavIconMotion.bounce => ScaleTransition(
        scale: Tween<double>(begin: 0.1, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
        ),
        child: widget.child,
      ),
      NavIconMotion.slide => FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
              ),
          child: widget.child,
        ),
      ),
      NavIconMotion.spin => RotationTransition(
        turns: Tween<double>(begin: 0, end: 0.5).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        ),
        child: widget.child,
      ),
    };
  }
}
