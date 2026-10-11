import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../library/collection_screen.dart';
import '../library/scan/add_music_actions.dart';
import '../library/scan/scan_banner.dart';
import '../library/track_list_view.dart';
import '../library/track_menu.dart';
import '../playback/now_playing_screen.dart';
import 'home_feed.dart';
import 'home_hero.dart';
import 'home_rows.dart';

/// The home screen: a hero featuring one track, then the listening feed: a
/// pill row with the listening time, the newest albums, a statistics card,
/// and a list that can show recent plays by day, the most played tracks
/// overall or lately, and the top artists and albums. Every number and row
/// comes from what is on, and has been played on, this device.
///
/// Typing in the search field at the top searches the library right here:
/// the results take the place of the feed until the search is closed.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  @override
  ConsumerState<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends ConsumerState<HomeScreen> {
  HomeSort _sort = HomeSort.recent;

  // The search field keeps its text, cursor and keyboard as it moves between
  // the hero and the top of the results.
  final _searchFieldKey = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  bool get _searching => _query.trim().isNotEmpty;

  /// Leaves the search, if one is open. Returns whether there was one, so
  /// the back button can close a search before it does anything else.
  bool closeSearch() {
    if (!_searching && !_searchFocus.hasFocus) return false;
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _query = '');
    return true;
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The search field, drawn for the dark hero or for the page it sits on.
  Widget _searchField({required bool onHero}) {
    final palette = context.noc;
    final color = onHero ? Colors.white : palette.textPrimary;
    final faint = onHero ? Colors.white70 : palette.textSecondary;
    final field = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: faint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: _searchFieldKey,
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              cursorColor: color,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color),
              decoration: InputDecoration.collapsed(
                hintText: 'Search tracks, artists, albums…',
                hintStyle: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: faint),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: 'Search your library',
      child: onHero
          ? Frosted(child: field)
          : DecoratedBox(
              decoration: ShapeDecoration(
                color: palette.glass,
                shape: StadiumBorder(
                  side: BorderSide(color: palette.glassBorder),
                ),
              ),
              child: field,
            ),
    );
  }

  /// The rows of the list in its current mode, and whether they are still
  /// being read.
  (List<HomeRow>, bool) _rows(Track? nowPlaying) {
    switch (_sort) {
      case HomeSort.recent:
        final log = ref.watch(playLogProvider);
        return (
          recentRows(
            log.value ?? const [],
            now: DateTime.now(),
            nowPlaying: nowPlaying,
          ),
          log.isLoading,
        );
      case HomeSort.mostPlayed:
        final tracks = ref.watch(mostPlayedProvider);
        return (
          rankedRows([
            for (final track in tracks.value ?? const <Track>[])
              (track: track, plays: track.playCount),
          ], nowPlaying: nowPlaying),
          tracks.isLoading,
        );
      case HomeSort.last7Days || HomeSort.last30Days:
        final ranked = ref.watch(
          topTracksInDaysProvider(_sort == HomeSort.last7Days ? 7 : 30),
        );
        return (
          rankedRows(ranked.value ?? const [], nowPlaying: nowPlaying),
          ranked.isLoading,
        );
      case HomeSort.topArtists:
        final artists = ref.watch(topGroupsProvider(TrackGroup.artist));
        return (
          [for (final artist in artists.value ?? const []) ArtistRow(artist)],
          artists.isLoading,
        );
      case HomeSort.topAlbums:
        final albums = ref.watch(topGroupsProvider(TrackGroup.album));
        return (
          [for (final album in albums.value ?? const []) AlbumRow(album)],
          albums.isLoading,
        );
    }
  }

  void _openGroup(TrackGroup group, String name) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupScreen(group: group, name: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(libraryStatsProvider);
    final currentId = ref.watch(currentTrackIdProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    Future<void> shuffleAll() async {
      final all = await ref.read(allTracksProvider.future);
      if (all.isEmpty) return;
      final handler = ref.read(audioHandlerProvider);
      await handler.playTracks(all);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
    }

    // Shown while there is no track to feature: an empty or loading library.
    final header = _Header(onOpenSearch: widget.onOpenSearch);

    final summary = stats.value;
    if (stats.isLoading && summary == null) {
      return Column(
        children: [
          header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }
    if (summary == null || summary.trackCount == 0) {
      return Column(
        children: [
          header,
          const ScanBanner(),
          Expanded(
            child: EmptyState(
              icon: Icons.graphic_eq_rounded,
              title: 'Welcome to NocTune',
              message: Theme.of(context).platform == TargetPlatform.android
                  ? 'Scan this device to build your library. Your music '
                        'stays on the device.'
                  : 'Import audio files, or copy them into the NocTune '
                        'folder in the Files app, to build your library.',
              action: const AddMusicActions(),
            ),
          ),
        ],
      );
    }

    if (_searching) {
      final query = _query.trim();
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
              child: Row(
                children: [
                  Expanded(child: _searchField(onHero: false)),
                  TextButton(
                    onPressed: closeSearch,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TrackListView(
                tracks: ref.watch(searchResultsProvider(query)),
                empty: EmptyState(
                  icon: Icons.music_off_outlined,
                  title: 'No matches',
                  message: 'Nothing in your library matches "$query".',
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The hero features what is in the player; failing that, the last thing
    // played; failing that, the newest arrival.
    final playing = ref.watch(currentTrackProvider).value;
    final current = playing != null && playing.id == currentId ? playing : null;
    final lastPlayed = ref.watch(recentlyPlayedProvider).value?.firstOrNull;
    final featured =
        current ??
        lastPlayed ??
        ref.watch(recentlyAddedProvider).value?.firstOrNull;
    final isPlaying = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final albums = ref.watch(recentAlbumsProvider).value ?? const [];
    final favourites = (ref.watch(favoritesProvider).value ?? const <Track>[])
        .take(30)
        .toList();

    final (rows, loading) = _rows(current);
    // Tapping a track plays the list from there, in the order shown.
    final queue = [
      for (final row in rows)
        if (row is TrackRow) row.track,
    ];
    final queueIndex = <HomeRow, int>{};
    for (final row in rows) {
      if (row is TrackRow) queueIndex[row] = queueIndex.length;
    }

    Widget buildRow(BuildContext context, int index) {
      final row = rows[index];
      return KeyedSubtree(
        key: ValueKey(row.key),
        child: switch (row) {
          DateHeaderRow(:final label) => HomeDateHeader(label: label),
          TrackRow(:final track, :final badge, :final isNowPlaying) =>
            HomeTrackRow(
              track: track,
              badge: badge,
              isNowPlaying: isNowPlaying,
              isPlaying: isPlaying,
              // The track in the player opens the player rather than
              // starting itself over.
              onTap: isNowPlaying
                  ? () => showNowPlaying(context)
                  : () => ref
                        .read(audioHandlerProvider)
                        .playTracks(queue, initialIndex: queueIndex[row]!),
              onMenu: () => showTrackMenu(context, ref, track),
            ),
          AlbumRow(:final album) => HomeGroupRow(
            group: album,
            isArtist: false,
            onTap: () => _openGroup(TrackGroup.album, album.name),
          ),
          ArtistRow(:final artist) => HomeGroupRow(
            group: artist,
            isArtist: true,
            onTap: () => _openGroup(TrackGroup.artist, artist.name),
          ),
        },
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: featured == null
                  ? header
                  : HomeHero(
                      track: featured,
                      isCurrent: current != null,
                      eyebrow: current != null
                          ? (isPlaying ? 'NOW PLAYING' : 'PAUSED')
                          : (lastPlayed != null
                                ? 'JUMP BACK IN'
                                : 'RECENTLY ADDED'),
                      search: _searchField(onHero: true),
                      onPlay: () =>
                          ref.read(audioHandlerProvider).playTracks([featured]),
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            SliverToBoxAdapter(child: HomeHeaderRow(onShuffleAll: shuffleAll)),
            const SliverToBoxAdapter(child: ScanBanner()),
            if (albums.isNotEmpty)
              SliverToBoxAdapter(
                child: HomeShelf(
                  title: 'Albums',
                  items: [
                    for (final album in albums)
                      (
                        artPath: album.artPath,
                        title: album.name,
                        subtitle: album.artist,
                        onTap: () => _openGroup(TrackGroup.album, album.name),
                      ),
                  ],
                  onSeeAll: widget.onOpenLibrary,
                ),
              ),
            if (favourites.isNotEmpty)
              SliverToBoxAdapter(
                child: HomeShelf(
                  title: 'Favourites',
                  items: [
                    // Tapping one plays the favourites from there.
                    for (final (index, track) in favourites.indexed)
                      (
                        artPath: track.artPath,
                        title: track.title,
                        subtitle: track.displayArtist,
                        onTap: () => ref
                            .read(audioHandlerProvider)
                            .playTracks(favourites, initialIndex: index),
                      ),
                  ],
                  onSeeAll: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FavouritesScreen(),
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: HomeStatsCard(
                stats: summary,
                onOpenLibrary: widget.onOpenLibrary,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // One rounded container holding the list heading and its rows.
            // Rows are built lazily as they scroll into view.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: DecoratedSliver(
                decoration: ShapeDecoration(
                  color: context.feedCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: context.feedRim,
                  ),
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      sliver: SliverToBoxAdapter(
                        child: HomeListHeader(
                          sort: _sort,
                          onSortChanged: (sort) => setState(() => _sort = sort),
                        ),
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            loading ? 'Loading…' : 'No tracks yet',
                            textAlign: TextAlign.center,
                            style: FlexType.bodyLarge.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        sliver: SliverList.builder(
                          itemCount: rows.length,
                          itemBuilder: buildRow,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
          ],
        ),
      ),
    );
  }
}

/// The rounded header panel shown before there is a track to feature: the
/// app's name and a way into search.
class _Header extends StatelessWidget {
  const _Header({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.glassSolid, palette.background],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'NocTune',
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontSize: 34),
                  ),
                ),
              ),
              _RoundAction(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: onOpenSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Pressable(
        semanticLabel: label,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.background.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: palette.textPrimary),
        ),
      ),
    );
  }
}
