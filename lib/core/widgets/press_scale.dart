import 'package:flutter/material.dart';

import '../motion.dart';

/// Lets [child] dip while a finger is on it and spring back, a little past
/// its size and home, when the finger lifts. It only watches the pointer:
/// the tap itself is still [child]'s. With reduced motion on, it stays still.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.88});

  final Widget child;

  /// The size it dips to, as a share of its own.
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? widget.scale : 1,
        duration: _pressed ? pressDown : pressRelease,
        curve: _pressed ? Curves.easeOut : pressSpring,
        child: widget.child,
      ),
    );
  }
}

/// How long a pressed control takes to dip.
const pressDown = Duration(milliseconds: 90);

/// How long a released control takes to spring back and settle.
const pressRelease = Duration(milliseconds: 420);

/// The way back from a press: quick, a touch past where it started, then
/// home.
const pressSpring = SpringCurve(frequency: 22, seconds: 0.42, damping: 0.55);
