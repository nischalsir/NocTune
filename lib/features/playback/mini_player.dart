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
/// Tapping it opens the full player; swiping it sideways stops playback and
/// clears the queue. On wide windows it grows into a full bar with a
/// scrubber. It takes no space when the queue is empty.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.compact = false});

  /// Squeezed between the two side buttons while the tabs are folded away.
  final bool compact;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  // A swiped-away bar must leave the tree at once, a frame or two before the
  // player reports the queue empty. Remember which track was dismissed.
  String? _dismissedId;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) {
      // The queue really is empty now; the same track may be played again.
      _dismissedId = null;
      return const SizedBox.shrink();
    }
    if (item.id == _dismissedId) return const SizedBox.shrink();

    return Dismissible(
      key: ValueKey('mini-player-${item.id}'),
      onDismissed: (_) {
        setState(() => _dismissedId = item.id);
        ref.read(audioHandlerProvider).clearQueue();
      },
      child: GlassPanel(
        chrome: true,
        padding: EdgeInsets.zero,
        radius: 26,
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 640
              ? _WideBar(item: item)
              : _CompactBar(item: item, tight: widget.compact),
        ),
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
            child: Artwork(
              path: item.artUri?.toFilePath(),
              size: 46,
              radius: 14,
            ),
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
  const _CompactBar({required this.item, required this.tight});

  final MediaItem item;
  final bool tight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              Expanded(child: _TrackSummary(item: item)),
              const SizedBox(width: 8),
              const PlayPauseButton(width: 52, height: 44),
              // With the side buttons showing there is only room for one.
              if (!tight) ...[
                const SizedBox(width: 8),
                SquircleButton(
                  icon: Icons.skip_next_rounded,
                  label: 'Next',
                  width: 46,
                  height: 44,
                  onTap: () => ref.read(audioHandlerProvider).skipToNext(),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: _TrackSummary(item: item)),
          const SizedBox(width: 44, child: ShuffleButton(height: 44)),
          const SizedBox(width: 10),
          const PrimaryTransport(dense: true),
          const SizedBox(width: 10),
          const SizedBox(width: 44, child: RepeatButton(height: 44)),
          const SizedBox(width: 18),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: LinearProgressIndicator(
        value: total == 0
            ? 0
            : (position.inMilliseconds / total).clamp(0.0, 1.0),
        minHeight: 2.5,
        borderRadius: BorderRadius.circular(2),
        backgroundColor: Colors.transparent,
        color: context.noc.accent,
      ),
    );
  }
}
