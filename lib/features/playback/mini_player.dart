import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/artwork.dart';
import '../../third_party/spotiflac/mornye_chrome.dart';
import '../../third_party/spotiflac/mornye_theme.dart';
import '../../third_party/spotiflac/runtime_profile_provider.dart';
import 'now_playing_route.dart';
import 'now_playing_screen.dart';

/// The player bar that sits on top of the navigation bar while something is
/// loaded. Tapping it opens the full player; swiping it sideways stops
/// playback and clears the queue. It takes no space when the queue is empty.
///
/// Its structure follows the mini-player of the navigation bar it belongs
/// to (see `third_party/spotiflac`): a glass capsule holding the cover,
/// title and artist, play/pause and, when there is room, next.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.compact = false, this.bottomPadding = 8});

  /// Squeezed between the two side buttons while the tabs are folded away.
  final bool compact;
  final double bottomPadding;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  // Hides the bar in the frames between a swipe-dismiss and the player
  // reporting the queue empty: a dismissed Dismissible must leave the tree
  // at once. Playing the same track again shows the bar normally.
  String? _dismissedItemId;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final isLoading = ref.watch(
      playbackStateProvider.select((state) {
        final processing = state.value?.processingState;
        return processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;
      }),
    );
    if (item.id == _dismissedItemId && !isPlaying) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final compact = widget.compact;

    final player = Dismissible(
      key: ValueKey('mini-player-${item.id}'),
      onDismissed: (_) {
        setState(() => _dismissedItemId = item.id);
        ref.read(audioHandlerProvider).clearQueue();
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showNowPlaying(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            child: Row(
              children: [
                Hero(
                  tag: kNowPlayingArtworkHero,
                  child: Artwork(
                    path: item.artUri?.toFilePath(),
                    size: MornyeTheme.tokens.coverMini,
                    radius: 6,
                  ),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.artist ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Color.lerp(
                            colorScheme.onSurfaceVariant,
                            colorScheme.onSurface,
                            colorScheme.brightness == Brightness.dark
                                ? 0.7
                                : 0.6,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  color: colorScheme.onSurface,
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(
                          isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                        ),
                  onPressed: isLoading
                      ? null
                      : () {
                          final handler = ref.read(audioHandlerProvider);
                          isPlaying ? handler.pause() : handler.play();
                        },
                ),
                if (!compact)
                  IconButton(
                    color: colorScheme.onSurface,
                    tooltip: 'Next',
                    icon: const Icon(CupertinoIcons.forward_fill),
                    onPressed: () =>
                        ref.read(audioHandlerProvider).skipToNext(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: MornyeGlass.navigation(
        strongTint: true,
        tintOpacity: MornyeTheme.chromeOpacity(context),
        blurEnabled: ref.watch(mornyeBlurEnabledProvider),
        child: player,
      ),
    );
  }
}
