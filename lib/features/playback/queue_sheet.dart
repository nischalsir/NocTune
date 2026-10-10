import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import 'noc_audio_handler.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: context.noc.glassSolid,
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.8, child: QueueSheet()),
);

/// The play queue: tap to jump, drag the handle to reorder, swipe to remove.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(queueProvider).value ?? const [];
    final state = ref.watch(playbackStateProvider).value;
    final currentIndex = state?.queueIndex;
    NocAudioHandler handler() => ref.read(audioHandlerProvider);
    final palette = context.noc;
    final text = Theme.of(context).textTheme;

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
                      handler().moveQueueItem(from, to),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isCurrent = index == currentIndex;
                    return Dismissible(
                      // The same track can be queued twice, so the position
                      // is part of the key.
                      key: ValueKey('$index:${item.id}'),
                      background: ColoredBox(color: palette.accent),
                      onDismissed: (_) => handler().removeQueueItemAt(index),
                      child: ListTile(
                        onTap: () => handler().skipToQueueItem(index),
                        leading: Artwork(
                          path: item.artUri?.toFilePath(),
                          size: 44,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            color: isCurrent ? palette.accent : null,
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
                    );
                  },
                ),
        ),
      ],
    );
  }
}
