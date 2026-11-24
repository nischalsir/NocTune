import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import 'noc_audio_handler.dart';
import 'playback_mapping.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.noc.glassSolid,
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.8, child: QueueSheet()),
);

/// The play queue: tap to jump, drag the handle to reorder, swipe to remove.
///
/// A move or a removal shows at once, in the frame the finger lets go,
/// rather than when the player reports its new queue a moment later: the
/// row would otherwise jump back to where it was and then over again.
class QueueSheet extends ConsumerStatefulWidget {
  const QueueSheet({super.key});

  @override
  ConsumerState<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<QueueSheet> {
  // The queue as the user has just left it, until the player's catches up.
  List<MediaItem>? _pending;
  int? _pendingIndex;

  NocAudioHandler get _handler => ref.read(audioHandlerProvider);

  void _move(List<MediaItem> items, int? current, int from, int to) {
    setState(() {
      // [to] counts the list without the moved entry, as the player does.
      final next = [...items];
      next.insert(to, next.removeAt(from));
      _pending = next;
      _pendingIndex = current == null
          ? null
          : _indexAfterMove(current, from, to);
    });
    _handler.moveQueueItem(from, to);
  }

  void _remove(List<MediaItem> items, int? current, int index) {
    setState(() {
      _pending = [...items]..removeAt(index);
      _pendingIndex = current == null || current == index
          ? null
          : (current > index ? current - 1 : current);
    });
    _handler.removeQueueItemAt(index);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(queueProvider, (_, _) {
      if (_pending != null) setState(() => _pending = _pendingIndex = null);
    });
    final reported = ref.watch(queueProvider).value ?? const [];
    final items = _pending ?? reported;
    final state = ref.watch(playbackStateProvider).value;
    final currentIndex = _pending != null ? _pendingIndex : state?.queueIndex;
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final fade = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);

    // The same track can be queued twice: each entry is known by the track
    // and how many times it has come up before it, which stays the same as
    // other entries move or go.
    final seen = <String, int>{};
    final keys = [
      for (final item in items)
        '${item.id}#${seen.update(item.id, (n) => n + 1, ifAbsent: () => 0)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Queue · ${items.length} ${items.length == 1 ? 'track' : 'tracks'}',
            style: text.titleLarge,
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'The queue is empty',
                  message: 'Play something from your library to fill it.',
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  onReorderItem: (from, to) =>
                      _move(items, currentIndex, from, to),
                  // The row being dragged lifts off the list.
                  proxyDecorator: (child, _, animation) => AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final lift = Curves.easeOut.transform(animation.value);
                      return Transform.scale(
                        scale: 1 + 0.03 * lift,
                        child: Material(
                          color: Color.lerp(
                            palette.glassSolid,
                            palette.accent,
                            0.08 * lift,
                          ),
                          elevation: 10 * lift,
                          shadowColor: Colors.black54,
                          borderRadius: BorderRadius.circular(14),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isCurrent = index == currentIndex;
                    return Dismissible(
                      key: ValueKey(keys[index]),
                      background: const _RemoveBackground(
                        alignment: Alignment.centerLeft,
                      ),
                      secondaryBackground: const _RemoveBackground(
                        alignment: Alignment.centerRight,
                      ),
                      onDismissed: (_) => _remove(items, currentIndex, index),
                      // The current track's row is filled with the accent,
                      // and the fill moves over when the track changes.
                      child: AnimatedContainer(
                        duration: fade,
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(
                            alpha: isCurrent ? 0.14 : 0,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        // Its own Material, so the tap's ripple shows over
                        // the fill.
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            onTap: () => _handler.skipToQueueItem(index),
                            leading: Artwork(
                              path: artUriToPathOrUrl(item.artUri),
                              size: 44,
                            ),
                            title: TweenAnimationBuilder<Color?>(
                              tween: ColorTween(
                                end: isCurrent
                                    ? palette.accent
                                    : text.titleSmall?.color,
                              ),
                              duration: fade,
                              builder: (context, color, _) => Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.copyWith(color: color),
                              ),
                            ),
                            subtitle: Text(
                              item.artist ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: Semantics(
                                label: 'Reorder ${item.title}',
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// What shows behind a row as it is swiped away.
class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.remove_circle_outline_rounded, color: palette.onAccent),
    );
  }
}

/// Where the entry at [current] is once the one at [from] has been taken
/// out and put back at [to].
int _indexAfterMove(int current, int from, int to) {
  if (current == from) return to;
  final afterRemoval = current > from ? current - 1 : current;
  return to <= afterRemoval ? afterRemoval + 1 : afterRemoval;
}
