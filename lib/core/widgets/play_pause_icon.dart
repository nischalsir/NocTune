import 'package:flutter/material.dart';

/// The play triangle and the pause bars, morphing from one into the other
/// when [playing] changes instead of swapping. With reduced motion on, it
/// swaps.
class PlayPauseIcon extends StatefulWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    this.size = 24,
    this.color,
  });

  final bool playing;
  final double size;
  final Color? color;

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final _morph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _morph.value = widget.playing ? 1 : 0;
    } else {
      _morph.animateTo(widget.playing ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  // Centred in a box of its size, as an [Icon] is, so a button that
  // stretches it to its own size still has it in the middle.
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: Center(
      child: AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _morph,
        size: widget.size,
        color: widget.color,
      ),
    ),
  );
}
