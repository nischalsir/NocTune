import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
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
  genres('Genres'),
  folders('Folders');

  const LibrarySection(this.label);

  final String label;
}

/// The whole library, browsable by track, album, artist, playlist, genre or
/// folder, with the favourites a tap away and a search of its own.
///
/// From the top: the title, a wide search button with scanning and
/// sorting on its right, each with a word saying what it does, the chips,
/// and the list they choose. The chosen chip is kept across launches.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _sectionKey = 'library_section';

  late LibrarySection _section =
      LibrarySection.values.asNameMap()[ref
          .read(sharedPreferencesProvider)
          .getString(_sectionKey)] ??
      LibrarySection.tracks;

  void _choose(LibrarySection section) {
    setState(() => _section = section);
    ref.read(sharedPreferencesProvider).setString(_sectionKey, section.name);
  }

  // The search takes the place of the buttons and title while it is open,
  // and its results the place of the list once something is typed.
  bool _searching = false;
  String _query = '';

  void _closeSearch() => setState(() {
    _searching = false;
    _query = '';
  });

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(trackOrderProvider);
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final scanning = ref.watch(scanControllerProvider) is ScanRunning;
    final scanController = ref.read(scanControllerProvider.notifier);
    final query = _query.trim();

    // Back closes an open search before it leaves the library.
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'Search your library',
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: palette.glass,
                            shape: StadiumBorder(
                              side: BorderSide(color: palette.glassBorder),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 20,
                                  color: palette.textSecondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    autofocus: true,
                                    onChanged: (value) =>
                                        setState(() => _query = value),
                                    textInputAction: TextInputAction.search,
                                    style: text.bodyMedium,
                                    decoration: InputDecoration.collapsed(
                                      hintText:
                                          'Search tracks, artists, albums…',
                                      hintStyle: text.bodyMedium?.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _closeSearch,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Your library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Row(
                  children: [
                    // Wide, like the search field it opens into.
                    Expanded(
                      child: _HeaderButton(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        tooltip: 'Search the library',
                        wide: true,
                        onTap: () => setState(() => _searching = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeaderButton(
                      icon: Icons.refresh_rounded,
                      label: 'Scan',
                      tooltip: 'Rescan library',
                      onTap: scanning ? null : scanController.scan,
                    ),
                    if (_section == LibrarySection.tracks) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<TrackSort>(
                        tooltip: 'Sort tracks',
                        onSelected: ref
                            .read(trackOrderProvider.notifier)
                            .select,
                        itemBuilder: (context) => [
                          for (final sort in TrackSort.values)
                            CheckedPopupMenuItem(
                              value: sort,
                              checked: sort == order.sort,
                              child: Text(
                                sort == order.sort
                                    ? '${sort.label} '
                                          '${order.ascending ? '↑' : '↓'}'
                                    : sort.label,
                              ),
                            ),
                        ],
                        child: const _HeaderPill(
                          icon: Icons.sort_rounded,
                          label: 'Sort',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (query.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (final section in LibrarySection.values) ...[
                      if (section != LibrarySection.values.first)
                        const SizedBox(width: 8),
                      _SectionChip(
                        label: section.label,
                        selected: section == _section,
                        onTap: () => _choose(section),
                      ),
                      // The favourites are a page of their own, opened from
                      // their place among the chips.
                      if (section == LibrarySection.playlists) ...[
                        const SizedBox(width: 8),
                        _SectionChip(
                          label: 'Favourites',
                          selected: false,
                          onTap: () => _open(const FavouritesScreen()),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            const ScanBanner(),
            Expanded(
              child: query.isNotEmpty
                  ? TrackListView(
                      tracks: ref.watch(searchResultsProvider(query)),
                      playButtons: true,
                      empty: EmptyState(
                        icon: Icons.music_off_outlined,
                        title: 'No matches',
                        message: 'Nothing in your library matches "$query".',
                      ),
                    )
                  : switch (_section) {
                      LibrarySection.tracks => TrackListView(
                        tracks: ref.watch(allTracksProvider),
                        playButtons: true,
                        empty: const EmptyState(
                          icon: Icons.library_music_outlined,
                          title: 'No music yet',
                          message: 'Add music to see your tracks here.',
                          action: AddMusicActions(),
                        ),
                      ),
                      LibrarySection.albums => const _GroupList(
                        TrackGroup.album,
                      ),
                      LibrarySection.artists => const _GroupList(
                        TrackGroup.artist,
                      ),
                      LibrarySection.genres => const _GroupList(
                        TrackGroup.genre,
                      ),
                      LibrarySection.folders => const _GroupList(
                        TrackGroup.folder,
                      ),
                      LibrarySection.playlists => const _PlaylistList(),
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass button at the top of the library: an icon and the word for
/// what it does. Without [onTap] it is dimmed and does nothing.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  /// Fills the width it is given, its word in the quieter colour of a
  /// field's hint, as the search does.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    final pill = _HeaderPill(icon: icon, label: label, wide: wide);
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: onTap == null
          ? Opacity(opacity: 0.4, child: pill)
          : Pressable(semanticLabel: tooltip, onTap: onTap, child: pill),
    );
  }
}

/// The face of a header button, in the glass finish of the chips below it.
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final color = wide ? palette.textSecondary : palette.textPrimary;
    return Frosted(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        child: Row(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the pills that choose what the library lists: filled with the
/// accent when it is the one chosen, glass otherwise.
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? palette.onAccent : palette.textPrimary,
        ),
      ),
    );
    return Semantics(
      selected: selected,
      child: Pressable(
        semanticLabel: label,
        onTap: onTap,
        child: selected
            ? DecoratedBox(
                decoration: ShapeDecoration(
                  color: palette.accent,
                  shape: const StadiumBorder(),
                ),
                child: content,
              )
            : Frosted(child: content),
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

/// The user's playlists, each pictured by its cover, with a way to start a
/// new one. A new playlist opens straight away, ready for tracks and a
/// cover.
class _PlaylistList extends ConsumerWidget {
  const _PlaylistList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const [];
    final text = Theme.of(context).textTheme;

    Future<void> create() async {
      final name = await askPlaylistName(context);
      if (name == null) return;
      final repository = ref.read(libraryRepositoryProvider);
      final id = await repository.createPlaylist(name);
      final created = (await repository.playlists()).firstWhere(
        (playlist) => playlist.id == id,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlaylistScreen(playlist: created),
        ),
      );
    }

    if (playlists.isEmpty) {
      return EmptyState(
        icon: Icons.queue_music_rounded,
        title: 'No playlists yet',
        message:
            'Make an album of your own: name it, pick its tracks and '
            'give it a cover.',
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
            leading: Artwork(path: playlist.cover, size: 48),
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
