// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// lib/widgets/animation_utils.dart. Copyright (c) 2026 zarzet, MIT licence.
// See LICENSE in this folder.

import 'package:flutter/material.dart';

/// Wraps a [Badge] child and plays a brief scale-bump whenever [count] changes.
class AnimatedBadge extends StatefulWidget {
  final int count;
  final Widget child;

  const AnimatedBadge({super.key, required this.count, required this.child});

  @override
  State<AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _previousCount = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != _previousCount && widget.count > _previousCount) {
      _controller.forward(from: 0);
    }
    _previousCount = widget.count;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}
