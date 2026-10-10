import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
import 'noc_audio_handler.dart';

/// A fully rounded frosted-glass button: a circle when square, a pill when
/// wide. It is the control shape used across the player.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.width = 48,
    this.height = 48,
    this.iconSize = 24,
    this.selected = false,
  });

  final IconData icon;

  /// Spoken by screen readers and used as the tooltip.
  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double iconSize;

  /// Draws the icon in the accent colour, for toggles that are on.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Pressable(
        semanticLabel: label,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Frosted(
            child: Icon(
              icon,
              size: iconSize,
              color: selected ? palette.accent : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The play/pause button: frosted glass carrying the accent, so it stays the
/// most prominent control. The icon swaps with a quick scale-and-fade rather
/// than snapping.
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, this.width = 84, this.height = 84});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final palette = context.noc;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Pressable(
      semanticLabel: playing ? 'Pause' : 'Play',
      onTap: () {
        final handler = ref.read(audioHandlerProvider);
        playing ? handler.pause() : handler.play();
      },
      child: SizedBox(
        width: width,
        height: height,
        child: Frosted(
          tint: palette.accent,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 160),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(playing),
              size: min(width, height) * 0.5,
              color: palette.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Previous, play/pause and next as three round buttons, the middle one
/// largest.
class PrimaryTransport extends ConsumerWidget {
  const PrimaryTransport({super.key, this.dense = false});

  /// Smaller buttons, for the player bar on wide screens.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    NocAudioHandler handler() => ref.read(audioHandlerProvider);
    final side = dense ? 44.0 : 66.0;
    final gap = dense ? 10.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassButton(
          icon: Icons.skip_previous_rounded,
          label: 'Previous',
          width: side,
          height: side,
          iconSize: dense ? 24 : 32,
          onTap: () => handler().skipToPrevious(),
        ),
        SizedBox(width: gap),
        PlayPauseButton(width: dense ? 52 : 88, height: dense ? 48 : 84),
        SizedBox(width: gap),
        GlassButton(
          icon: Icons.skip_next_rounded,
          label: 'Next',
          width: side,
          height: side,
          iconSize: dense ? 24 : 32,
          onTap: () => handler().skipToNext(),
        ),
      ],
    );
  }
}

/// Toggles shuffle. Reports its state in its label so it is clear when on.
class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({super.key, this.height = 52});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffling = ref.watch(
      playbackStateProvider.select(
        (state) =>
            (state.value?.shuffleMode ?? AudioServiceShuffleMode.none) !=
            AudioServiceShuffleMode.none,
      ),
    );
    return GlassButton(
      icon: Icons.shuffle_rounded,
      label: shuffling ? 'Shuffle is on' : 'Shuffle is off',
      width: double.infinity,
      height: height,
      selected: shuffling,
      onTap: () => ref
          .read(audioHandlerProvider)
          .setShuffleMode(
            shuffling
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
    );
  }
}

/// Cycles repeat: off → whole queue → this track → off.
class RepeatButton extends ConsumerWidget {
  const RepeatButton({super.key, this.height = 52});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repeat = ref.watch(
      playbackStateProvider.select(
        (state) => state.value?.repeatMode ?? AudioServiceRepeatMode.none,
      ),
    );
    return GlassButton(
      icon: repeat == AudioServiceRepeatMode.one
          ? Icons.repeat_one_rounded
          : Icons.repeat_rounded,
      label: switch (repeat) {
        AudioServiceRepeatMode.none => 'Repeat is off',
        AudioServiceRepeatMode.one => 'Repeating this track',
        _ => 'Repeating the queue',
      },
      width: double.infinity,
      height: height,
      selected: repeat != AudioServiceRepeatMode.none,
      onTap: () =>
          ref.read(audioHandlerProvider).setRepeatMode(switch (repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
            _ => AudioServiceRepeatMode.one,
          }),
    );
  }
}

/// The scrubber: a thick track with a bar-shaped handle. While a finger is on
/// it the handle follows the finger, and the player only seeks on release.
class SeekBar extends ConsumerStatefulWidget {
  const SeekBar({super.key, required this.duration, this.inline = false});

  final Duration duration;

  /// Lay the times out beside the slider instead of beneath it.
  final bool inline;

  @override
  ConsumerState<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<SeekBar> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final totalMs = widget.duration.inMilliseconds.toDouble();
    final shownMs = (_dragMs ?? position.inMilliseconds.toDouble())
        .clamp(0.0, max(totalMs, 0.0))
        .toDouble();
    final palette = context.noc;
    final times = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final elapsed = Text(
      formatDuration(Duration(milliseconds: shownMs.round())),
      style: times,
    );
    // Counts down what is left, like the reference player.
    final remaining = Text(
      totalMs > 0
          ? '-${formatDuration(Duration(milliseconds: (totalMs - shownMs).round()))}'
          : '–:––',
      style: times,
    );
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: widget.inline ? 8 : 14,
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.glass,
        thumbColor: palette.accent,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        // The current Material slider: thick track, gap and bar handle.
        // ignore: deprecated_member_use
        year2023: false,
        padding: EdgeInsets.symmetric(vertical: widget.inline ? 10 : 14),
        max: totalMs > 0 ? totalMs : 1,
        value: totalMs > 0 ? shownMs : 0,
        // Disabled until the length is known.
        onChanged: totalMs > 0
            ? (value) => setState(() => _dragMs = value)
            : null,
        onChangeEnd: (value) {
          ref
              .read(audioHandlerProvider)
              .seek(Duration(milliseconds: value.round()));
          setState(() => _dragMs = null);
        },
        semanticFormatterCallback: (value) =>
            formatDuration(Duration(milliseconds: value.round())),
      ),
    );

    if (widget.inline) {
      return Row(
        children: [
          elapsed,
          const SizedBox(width: 10),
          Expanded(child: slider),
          const SizedBox(width: 10),
          remaining,
        ],
      );
    }
    return Column(
      children: [
        slider,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [elapsed, remaining],
        ),
      ],
    );
  }
}
