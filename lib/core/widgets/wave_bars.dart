import 'dart:math';

import 'package:flutter/material.dart';

/// A few sound bars that rise and fall while [playing], like a small level
/// meter. They are a sign that music is running, not a reading of the actual
/// audio. Paused, or with reduced motion on, they rest at a fixed height.
class WaveBars extends StatefulWidget {
  const WaveBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = const Size(22, 18),
    this.barCount = 4,
  });

  final bool playing;
  final Color color;
  final Size size;
  final int barCount;

  @override
  State<WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<WaveBars>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  void _sync() {
    final animate = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WaveBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = widget.playing && !MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      // Repaints only this small area as the bars move.
      child: RepaintBoundary(
        child: CustomPaint(
          size: widget.size,
          painter: _WavePainter(
            phase: _controller,
            moving: moving,
            color: widget.color,
            barCount: widget.barCount,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.phase,
    required this.moving,
    required this.color,
    required this.barCount,
  }) : super(repaint: phase);

  final Animation<double> phase;
  final bool moving;
  final Color color;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final slot = size.width / barCount;
    final barWidth = slot * 0.56;
    for (var i = 0; i < barCount; i++) {
      // Two sine waves at different speeds, offset per bar, so the bars
      // move independently instead of in a visible loop.
      final t = phase.value * 2 * pi;
      final offset = i * 1.7;
      final level = moving
          ? 0.5 + 0.3 * sin(t + offset) + 0.2 * sin(2 * t + offset * 2.3)
          : 0.32;
      final height = size.height * level.clamp(0.18, 1.0);
      canvas.drawRRect(
        RRect.fromLTRBR(
          slot * i + (slot - barWidth) / 2,
          (size.height - height) / 2,
          slot * i + (slot + barWidth) / 2,
          (size.height + height) / 2,
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      moving != oldDelegate.moving ||
      color != oldDelegate.color ||
      barCount != oldDelegate.barCount;
}
