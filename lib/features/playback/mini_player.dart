import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/pressable.dart';
import 'now_playing_route.dart';
import 'now_playing_screen.dart';
import 'transport_controls.dart';

/// The glass player bar that stays on screen while something is loaded.
/// On phones it is compact; on wider windows it grows into the full bar with
/// shuffle, repeat and a scrubber. It collapses to nothing with an empty queue.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();

    return GlassPanel(
      chrome: true,
      padding: EdgeInsets.zero,
      radius: 18,
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 640
            ? _WideBar(item: item)
            : _CompactBar(item: item),
      ),
    );
  }
}

/// Artwork and titles; tapping them opens the full player. The cover is the
/// shared element that grows into the player's artwork.
class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      semanticLabel: 'Open player. ${item.title}, ${item.artist ?? ''}',
      onTap: () => showNowPlaying(context),
      child: Row(
        children: [
          Hero(
            tag: kNowPlayingArtworkHero,
            child: Artwork(path: item.artUri?.toFilePath(), size: 44),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                Text(
                  item.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBar extends ConsumerWidget {
  const _CompactBar({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 8),
          child: Row(
            children: [
              Expanded(child: _TrackSummary(item: item)),
              IconButton(
                tooltip: 'Previous',
                onPressed: () =>
                    ref.read(audioHandlerProvider).skipToPrevious(),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const PlayPauseButton(size: 46),
              IconButton(
                tooltip: 'Next',
                onPressed: () => ref.read(audioHandlerProvider).skipToNext(),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ),
        _ProgressLine(duration: item.duration),
      ],
    );
  }
}

/// The full-width bar: track on the left, transport in the centre and the
/// scrubber on the right.
class _WideBar extends StatelessWidget {
  const _WideBar({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: _TrackSummary(item: item)),
          const TransportControls(dense: true),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: SeekBar(
              duration: item.duration ?? Duration.zero,
              inline: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hairline progress along the bottom edge. Kept separate so position ticks
/// repaint only this line, not the whole bar.
class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({required this.duration});

  final Duration? duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final total = duration?.inMilliseconds ?? 0;
    return LinearProgressIndicator(
      value: total == 0 ? 0 : (position.inMilliseconds / total).clamp(0.0, 1.0),
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: context.noc.accent,
    );
  }
}
