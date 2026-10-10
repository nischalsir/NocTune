import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../data/models/track.dart';
import '../playback/playback_mapping.dart';
import 'playlist_dialogs.dart';

/// Opens the actions for one track. Pass [playlistId] when the track is shown
/// inside a playlist, to offer removing it from that playlist.
Future<void> showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  int? playlistId,
}) {
  final handler = ref.read(audioHandlerProvider);
  final repository = ref.read(libraryRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);

  void confirm(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  return showModalBottomSheet<void>(
    context: context,
    // Above the navigation bar and mini-player, not inside the library tab.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.noc.glassSolid,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Play next'),
              onTap: () {
                handler.playNext(track);
                Navigator.of(sheetContext).pop();
                confirm('Playing next: ${track.title}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Add to queue'),
              onTap: () {
                handler.addQueueItem(mediaItemFromTrack(track));
                Navigator.of(sheetContext).pop();
                confirm('Added to queue: ${track.title}');
              },
            ),
            ListTile(
              leading: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(
                track.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
              ),
              onTap: () {
                repository.setFavorite(track.id, favorite: !track.isFavorite);
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Add to playlist…'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAddToPlaylist(context, ref, track);
              },
            ),
            if (playlistId != null)
              ListTile(
                leading: const Icon(Icons.playlist_remove_rounded),
                title: const Text('Remove from this playlist'),
                onTap: () {
                  repository.removeFromPlaylist(playlistId, track.id);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Details'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showTrackDetails(context, track);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows what is known about a track's file: its format, size and where it
/// is stored.
void showTrackDetails(BuildContext context, Track track) {
  final megabytes = (track.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
  final rows = <(String, String)>[
    ('Title', track.title),
    ('Artist', track.displayArtist),
    ('Album', track.displayAlbum),
    if (track.genre case final genre?) ('Genre', genre),
    if (track.year case final year?) ('Year', '$year'),
    ('Length', formatDuration(track.duration)),
    ('Audio', qualityLabel(track)),
    ('Size', '$megabytes MB'),
    ('Played', '${track.playCount} times'),
    ('File', track.fileName),
    ('Folder', track.folder),
  ];
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Track details'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    SelectableText(value),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
