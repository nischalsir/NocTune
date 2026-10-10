import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'playlist_dialogs.dart';
import 'track_list_view.dart';

/// A page listing the tracks of one album, artist, genre, folder or playlist.
class _CollectionPage extends StatelessWidget {
  const _CollectionPage({
    required this.title,
    required this.tracks,
    required this.empty,
    this.playlistId,
    this.actions = const [],
  });

  final String title;
  final AsyncValue<List<Track>> tracks;
  final Widget empty;
  final int? playlistId;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final count = tracks.value?.length;
    return NocBackdrop(
      // Its own Material, so the page works on whichever navigator shows it.
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (count != null)
                            Text(
                              '$count ${count == 1 ? 'track' : 'tracks'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
              Expanded(
                child: TrackListView(
                  tracks: tracks,
                  empty: empty,
                  playlistId: playlistId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tracks of one album, artist, genre or folder.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.group, required this.name});

  final TrackGroup group;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CollectionPage(
      // A folder is identified by its full path but titled by its name.
      title: group == TrackGroup.folder ? p.basename(name) : name,
      tracks: ref.watch(groupTracksProvider((group: group, name: name))),
      empty: const EmptyState(
        icon: Icons.music_off_outlined,
        title: 'Nothing here any more',
        message: 'These tracks are no longer in your library.',
      ),
    );
  }
}

/// One playlist, with rename and delete.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(libraryRepositoryProvider);
    // Follow renames made from this screen.
    final current =
        ref
            .watch(playlistsProvider)
            .value
            ?.where((candidate) => candidate.id == playlist.id)
            .firstOrNull ??
        playlist;

    return _CollectionPage(
      title: current.name,
      playlistId: playlist.id,
      tracks: ref.watch(playlistTracksProvider(playlist.id)),
      empty: const EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'This playlist is empty',
        message: 'Use the menu on any track and choose "Add to playlist".',
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Playlist options',
          onSelected: (action) async {
            if (action == 'rename') {
              final name = await askPlaylistName(
                context,
                initialName: current.name,
              );
              if (name != null) {
                await repository.renamePlaylist(current.id, name);
              }
            } else if (await _confirmDelete(context, current.name)) {
              await repository.deletePlaylist(current.id);
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
          ],
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "$name"?'),
      content: const Text(
        'The playlist will be deleted. The tracks stay in your library.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
