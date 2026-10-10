import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/pressable.dart';
import 'noc_audio_handler.dart';

/// The round accent-coloured play/pause button, ringed like a dashboard dial.
/// The icon swaps with a quick scale-and-fade rather than snapping.
class PlayPauseButton extends ConsumerWidget {
  const PlayPauseButton({super.key, this.size = 72});

  final double size;

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
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.07),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
          ),
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
              size: size * 0.5,
              color: palette.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shuffle, previous, play/pause, next and repeat.
class TransportControls extends ConsumerWidget {
  const TransportControls({super.key, this.dense = false});

  /// Smaller buttons packed together, for the player bar on wide screens.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateProvider).value;
    final shuffling =
        (state?.shuffleMode ?? AudioServiceShuffleMode.none) !=
        AudioServiceShuffleMode.none;
    final repeat = state?.repeatMode ?? AudioServiceRepeatMode.none;
    final palette = context.noc;
    NocAudioHandler handler() => ref.read(audioHandlerProvider);
    final skipSize = dense ? 28.0 : 38.0;

    return Row(
      mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: shuffling ? 'Shuffle is on' : 'Shuffle is off',
          isSelected: shuffling,
          color: shuffling ? palette.accent : palette.textSecondary,
          onPressed: () => handler().setShuffleMode(
            shuffling
                ? AudioServiceShuffleMode.none
                : AudioServiceShuffleMode.all,
          ),
          icon: const Icon(Icons.shuffle_rounded),
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: skipSize,
          onPressed: () => handler().skipToPrevious(),
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 0),
          child: PlayPauseButton(size: dense ? 48 : 72),
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: skipSize,
          onPressed: () => handler().skipToNext(),
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: switch (repeat) {
            AudioServiceRepeatMode.none => 'Repeat is off',
            AudioServiceRepeatMode.one => 'Repeating this track',
            _ => 'Repeating the queue',
          },
          isSelected: repeat != AudioServiceRepeatMode.none,
          color: repeat == AudioServiceRepeatMode.none
              ? palette.textSecondary
              : palette.accent,
          // Cycles off → whole queue → this track → off.
          onPressed: () => handler().setRepeatMode(switch (repeat) {
            AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
            AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
            _ => AudioServiceRepeatMode.one,
          }),
          icon: Icon(
            repeat == AudioServiceRepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ),
      ],
    );
  }
}

/// The scrubber. While a finger is on it the thumb follows the finger, and
/// the player only seeks on release.
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
    final times = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final elapsed = Text(
      formatDuration(Duration(milliseconds: shownMs.round())),
      style: times,
    );
    final total = Text(
      totalMs > 0 ? formatDuration(widget.duration) : '–:––',
      style: times,
    );
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
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
          Expanded(child: slider),
          total,
        ],
      );
    }
    return Column(
      children: [
        slider,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [elapsed, total],
          ),
        ),
      ],
    );
  }
}
