import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../data/models/track.dart';
import 'extension_controller.dart';
import 'extension_models.dart';

/// Displays active, failed, and completed extension downloads in a single
/// Mornye-style queue & history page.
class ExtensionDownloadsScreen extends ConsumerWidget {
  const ExtensionDownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(extensionControllerProvider);
    final controller = ref.read(extensionControllerProvider.notifier);
    final queue = state.downloadQueue;
    final allLibrary = ref.watch(allTracksProvider).value ?? const <Track>[];

    final activeItems = [
      for (final item in queue)
        if (item.isActive) item,
    ];
    final failedItems = [
      for (final item in queue)
        if (item.status == ExtensionDownloadStatus.failed) item,
    ];
    final completedItems = [
      for (final item in queue)
        if (item.status == ExtensionDownloadStatus.completed) item,
    ];
    final hasFinished = failedItems.isNotEmpty || completedItems.isNotEmpty;

    return NocBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          title: const Text('Download queue'),
          actions: [
            if (hasFinished)
              TextButton(
                onPressed: controller.clearFinishedDownloads,
                child: const Text('Clear finished'),
              ),
          ],
        ),
        body: queue.isEmpty
            ? const EmptyState(
                icon: Icons.downloading_rounded,
                title: 'No downloads in queue',
                message:
                    'Songs and albums you download from extensions appear here.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (activeItems.isNotEmpty) ...[
                    _SectionHeader('IN PROGRESS (${activeItems.length})'),
                    _QueueCard(
                      children: [
                        for (final (idx, item) in activeItems.indexed) ...[
                          if (idx > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: palette.glassBorder,
                            ),
                          _QueueItemTile(
                            item: item,
                            allLibrary: allLibrary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (failedItems.isNotEmpty) ...[
                    _SectionHeader('FAILED (${failedItems.length})'),
                    _QueueCard(
                      children: [
                        for (final (idx, item) in failedItems.indexed) ...[
                          if (idx > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: palette.glassBorder,
                            ),
                          _QueueItemTile(
                            item: item,
                            allLibrary: allLibrary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (completedItems.isNotEmpty) ...[
                    _SectionHeader('COMPLETED (${completedItems.length})'),
                    _QueueCard(
                      children: [
                        for (final (idx, item) in completedItems.indexed) ...[
                          if (idx > 0)
                            Divider(
                              height: 1,
                              indent: 64,
                              color: palette.glassBorder,
                            ),
                          _QueueItemTile(
                            item: item,
                            allLibrary: allLibrary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Material(
      color: palette.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.glassBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _QueueItemTile extends ConsumerWidget {
  const _QueueItemTile({
    required this.item,
    required this.allLibrary,
  });

  final ExtensionDownloadItem item;
  final List<Track> allLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final track = item.track;
    final controller = ref.read(extensionControllerProvider.notifier);

    final localMatch = allLibrary.cast<Track?>().firstWhere(
      (t) =>
          t != null &&
          (t.uri == item.filePath ||
              (t.title.toLowerCase() == track.title.toLowerCase() &&
                  (t.artist ?? '').toLowerCase() ==
                      track.artist.toLowerCase())),
      orElse: () => null,
    );

    final subtitleParts = <String>[
      if (track.artist.isNotEmpty) track.artist,
      if (track.providerName.isNotEmpty) track.providerName,
      switch (item.status) {
        ExtensionDownloadStatus.queued => 'Queued',
        ExtensionDownloadStatus.downloading => 'Downloading…',
        ExtensionDownloadStatus.completed => 'Saved to library',
        ExtensionDownloadStatus.failed => item.errorMessage ?? 'Failed',
      },
    ];

    return ListTile(
      leading: Artwork(
        path: localMatch?.artPath,
        size: 46,
        radius: 10,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleMedium,
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(
          color: item.status == ExtensionDownloadStatus.failed
              ? Theme.of(context).colorScheme.error
              : palette.textSecondary,
        ),
      ),
      onTap: item.status == ExtensionDownloadStatus.completed &&
              localMatch != null
          ? () => ref.read(audioHandlerProvider).playTracks([localMatch])
          : null,
      trailing: switch (item.status) {
        ExtensionDownloadStatus.queued ||
        ExtensionDownloadStatus.downloading =>
          const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ExtensionDownloadStatus.failed => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Retry ${track.title}',
                onPressed: () async {
                  try {
                    await controller.downloadTrack(track);
                  } on Object {
                    // Error state is recorded in downloadQueue.
                  }
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: 'Remove from queue',
                onPressed: () => controller.removeDownloadItem(item.uniqueKey),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ExtensionDownloadStatus.completed => IconButton(
            tooltip: localMatch != null ? 'Play ${track.title}' : 'Downloaded',
            onPressed: localMatch == null
                ? null
                : () => ref.read(audioHandlerProvider).playTracks([localMatch]),
            icon: Icon(
              localMatch != null
                  ? Icons.play_circle_fill_rounded
                  : Icons.download_done_rounded,
            ),
          ),
      },
    );
  }
}
