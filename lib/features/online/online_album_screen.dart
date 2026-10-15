import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pill_button.dart';
import '../library/track_tile.dart';
import 'download_action.dart';
import 'external_search.dart';
import 'online_album.dart';
import 'online_playback.dart';
import 'online_source.dart';

/// The tracks of an album or show found on the Internet Archive: its cover
/// and name, Play all and Download all, and every track with its own
/// download button.
class OnlineAlbumScreen extends ConsumerWidget {
  const OnlineAlbumScreen({super.key, required this.album});

  final OnlineAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(onlineAlbumProvider(album));
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: NocBackdrop(
        child: SafeArea(
          child: switch (results.value) {
            // Never expected: fetching catches its failures. Shown as one.
            null when results.hasError => _Empty(
              album: album,
              failure: OnlineFailure.unavailable,
            ),
            null => const Center(child: CircularProgressIndicator()),
            final results when results.items.isEmpty => _Empty(
              album: album,
              failure: results.failure,
            ),
            final results => _Tracks(
              album: album,
              tracks: results.tracks,
              offline: results.failure == OnlineFailure.offline,
            ),
          },
        ),
      ),
    );
  }
}

class _Tracks extends ConsumerWidget {
  const _Tracks({
    required this.album,
    required this.tracks,
    required this.offline,
  });

  final OnlineAlbum album;
  final List<OnlineTrack> tracks;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUri = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    // Rebuilds the rows as downloads start, finish or fail.
    final downloads = ref.watch(onlineDownloadsProvider);
    final paths = ref.watch(appPathsProvider);

    Future<void> play(int index) async {
      final outcome = await ref
          .read(onlinePlayerProvider)
          .play(tracks, index, offline: {if (offline) OnlineSourceId.archive});
      if (outcome == OnlinePlayOutcome.needsConnection && context.mounted) {
        say(
          context,
          '${tracks[index].title} needs an internet connection. '
          'Download it while online to play it offline.',
        );
      }
    }

    Future<void> downloadAll() async {
      final failed = await ref
          .read(onlineDownloadsProvider.notifier)
          .downloadAll(tracks);
      if (failed > 0 && context.mounted) {
        say(
          context,
          failed == 1
              ? "1 track couldn't be downloaded."
              : "$failed tracks couldn't be downloaded.",
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Header(album: album),
        if (offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              "You're offline. This list is from the last time it opened; "
              'only downloaded tracks can play.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: PillButton(
                  filled: true,
                  icon: Icons.play_arrow_rounded,
                  label: 'Play all',
                  // Offline, from the first track that is on the device.
                  onTap: () => play(
                    offline
                        ? max(
                            0,
                            tracks.indexWhere(
                              (track) =>
                                  downloadedFile(paths, track).existsSync(),
                            ),
                          )
                        : 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  icon: Icons.download_rounded,
                  label: 'Download all',
                  onTap: downloadAll,
                ),
              ),
            ],
          ),
        ),
        for (final (index, track) in tracks.indexed)
          Builder(
            builder: (context) {
              final file = downloadedFile(paths, track);
              final downloaded = file.existsSync();
              return Opacity(
                // Can't play right now: no connection and no copy here.
                opacity: offline && !downloaded ? 0.5 : 1,
                child: TrackTile(
                  track: streamedTrack(track),
                  isCurrent:
                      currentUri == '${track.streamUrl}' ||
                      (downloaded &&
                          currentUri == Uri.file(file.path).toString()),
                  playing: playing,
                  onTap: () => play(index),
                  action: DownloadAction(
                    track: track,
                    downloaded: downloaded,
                    offline: offline,
                    status: downloads[track.key],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.album});

  final OnlineAlbum album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final licence = album.licenceUrl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Artwork(path: null, url: album.imageUrl, size: 180, radius: 16),
          const SizedBox(height: 16),
          Text(
            album.title,
            textAlign: TextAlign.center,
            style: text.titleLarge,
          ),
          if (album.creator case final creator?) ...[
            const SizedBox(height: 4),
            Text(creator, textAlign: TextAlign.center, style: text.bodyMedium),
          ],
          const SizedBox(height: 4),
          Text(OnlineSourceId.archive.label, style: text.bodySmall),
          if (licence != null)
            TextButton(
              onPressed: () async {
                final opened = await ref.read(linkOpenerProvider)(
                  Uri.parse(licence),
                );
                if (!opened && context.mounted) {
                  say(context, "Couldn't open the licence.");
                }
              },
              child: const Text('Licence'),
            ),
        ],
      ),
    );
  }
}

/// No tracks to show: none could be fetched, or the item has none.
class _Empty extends ConsumerWidget {
  const _Empty({required this.album, required this.failure});

  final OnlineAlbum album;
  final OnlineFailure? failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = switch (failure) {
      null => 'This item has nothing NocTune can play.',
      OnlineFailure.offline => 'This needs an internet connection.',
      _ => "${OnlineSourceId.archive.label} couldn't be reached right now.",
    };
    return ListView(
      children: [
        _Header(album: album),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (failure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
            child: PillButton(
              icon: Icons.refresh_rounded,
              label: 'Try again',
              onTap: () => ref.invalidate(onlineAlbumProvider(album)),
            ),
          ),
      ],
    );
  }
}
