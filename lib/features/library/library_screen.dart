import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/repositories/library_repository.dart';
import 'collection_screen.dart';
import 'playlist_dialogs.dart';
import 'scan/add_music_actions.dart';
import 'scan/scan_banner.dart';
import 'scan/scan_controller.dart';
import 'track_list_view.dart';

/// The ways to browse the library, shown as filter chips.
enum LibrarySection {
  tracks('Tracks'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists'),
  favourites('Favourites'),
  genres('Genres'),
  folders('Folders');

  const LibrarySection(this.label);

  final String label;
}

/// The whole library, browsable by track, album, artist, playlist, favourite,
/// genre or folder.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  LibrarySection _section = LibrarySection.tracks;

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(trackOrderProvider);
    final text = Theme.of(context).textTheme;
    final scanning = ref.watch(scanControllerProvider) is ScanRunning;
    final scanController = ref.read(scanControllerProvider.notifier);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text('Library', style: text.headlineSmall)),
                IconButton(
                  tooltip: 'Import files',
                  onPressed: scanning ? null : scanController.importFiles,
                  icon: const Icon(Icons.file_open_outlined),
                ),
                IconButton(
                  tooltip: 'Rescan library',
                  onPressed: scanning ? null : scanController.scan,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (_section == LibrarySection.tracks)
                  PopupMenuButton<TrackSort>(
                    tooltip: 'Sort tracks',
                    icon: const Icon(Icons.sort_rounded),
                    onSelected: ref.read(trackOrderProvider.notifier).select,
                    itemBuilder: (context) => [
                      for (final sort in TrackSort.values)
                        CheckedPopupMenuItem(
                          value: sort,
                          checked: sort == order.sort,
                          child: Text(
                            sort == order.sort
                                ? '${sort.label} ${order.ascending ? '↑' : '↓'}'
                                : sort.label,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: LibrarySection.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final section = LibrarySection.values[index];
                return ChoiceChip(
                  label: Text(section.label),
                  selected: section == _section,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _section = section),
                );
              },
            ),
          ),
          const ScanBanner(),
          Expanded(
            child: switch (_section) {
              LibrarySection.tracks => TrackListView(
                tracks: ref.watch(allTracksProvider),
                empty: const EmptyState(
                  icon: Icons.library_music_outlined,
                  title: 'No music yet',
                  message: 'Add music to see your tracks here.',
                  action: AddMusicActions(),
                ),
              ),
              LibrarySection.favourites => TrackListView(
                tracks: ref.watch(favoritesProvider),
                empty: const EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'No favourites yet',
                  message: 'Tap the heart on a track you love to keep it here.',
                ),
              ),
              LibrarySection.albums => const _GroupList(TrackGroup.album),
              LibrarySection.artists => const _GroupList(TrackGroup.artist),
              LibrarySection.genres => const _GroupList(TrackGroup.genre),
              LibrarySection.folders => const _GroupList(TrackGroup.folder),
              LibrarySection.playlists => const _PlaylistList(),
            },
          ),
        ],
      ),
    );
  }
}

/// Albums, artists, genres or folders; tapping one opens its tracks.
class _GroupList extends ConsumerWidget {
  const _GroupList(this.group);

  final TrackGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ref
        .watch(trackGroupsProvider(group))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: "Couldn't load your library",
            message: '$error',
          ),
          data: (groups) {
            if (groups.isEmpty) {
              return EmptyState(
                icon: Icons.library_music_outlined,
                title: 'Nothing to show',
                message: switch (group) {
                  TrackGroup.genre => 'None of your tracks has a genre tag.',
                  TrackGroup.album => 'None of your tracks has an album tag.',
                  TrackGroup.artist => 'None of your tracks has an artist tag.',
                  TrackGroup.folder => 'Add music to browse it by folder.',
                },
              );
            }
            return ListView.builder(
              itemCount: groups.length,
              itemExtent: 68,
              itemBuilder: (context, index) {
                final summary = groups[index];
                final count =
                    '${summary.trackCount} '
                    '${summary.trackCount == 1 ? 'track' : 'tracks'}';
                return ListTile(
                  leading: Artwork(path: summary.artPath, size: 48),
                  title: Text(
                    group == TrackGroup.folder
                        ? p.basename(summary.name)
                        : summary.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  subtitle: Text(
                    group == TrackGroup.album && summary.artist != null
                        ? '${summary.artist} · $count'
                        : count,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          GroupScreen(group: group, name: summary.name),
                    ),
                  ),
                );
              },
            );
          },
        );
  }
}

class _PlaylistList extends ConsumerWidget {
  const _PlaylistList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final text = Theme.of(context).textTheme;

    Future<void> create() async {
      final name = await askPlaylistName(context);
      if (name != null) {
        await ref.read(libraryRepositoryProvider).createPlaylist(name);
      }
    }

    if (playlists.isEmpty) {
      return EmptyState(
        icon: Icons.queue_music_rounded,
        title: 'No playlists yet',
        message: 'Create a playlist, then add tracks from their menu.',
        action: FilledButton.icon(
          onPressed: create,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New playlist'),
        ),
      );
    }
    return ListView(
      children: [
        ListTile(
          leading: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.add_rounded),
          ),
          title: Text('New playlist', style: text.titleSmall),
          onTap: create,
        ),
        for (final playlist in playlists)
          ListTile(
            leading: const SizedBox.square(
              dimension: 48,
              child: Icon(Icons.queue_music_rounded),
            ),
            title: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall,
            ),
            subtitle: Text(
              '${playlist.trackCount} '
              '${playlist.trackCount == 1 ? 'track' : 'tracks'}',
              style: text.bodySmall,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlaylistScreen(playlist: playlist),
              ),
            ),
          ),
      ],
    );
  }
}
