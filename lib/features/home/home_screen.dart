import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../library/collection_screen.dart';
import '../library/scan/add_music_actions.dart';
import '../library/scan/scan_banner.dart';
import '../library/track_menu.dart';
import '../playback/now_playing_screen.dart';
import 'home_feed.dart';
import 'home_hero.dart';
import 'home_rows.dart';

/// The home screen: a hero featuring one track, then the listening feed: a
/// pill row with the listening time, a statistics card, and a list that can
/// show recent plays by day, the most played tracks overall or lately, and
/// the top artists and albums. Every number and row comes from what has been
/// played on this device.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenLibrary,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeSort _sort = HomeSort.recent;

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
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    Future<void> shuffleAll() async {
      final all = await ref.read(allTracksProvider.future);
      if (all.isEmpty) return;
      final handler = ref.read(audioHandlerProvider);
      await handler.playTracks(all);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
    }

    // Shown while there is no track to feature: an empty or loading library.
    final header = _Header(
      onOpenSearch: widget.onOpenSearch,
      onOpenSettings: widget.onOpenSettings,
    );

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
                      onOpenSearch: widget.onOpenSearch,
                      onOpenSettings: widget.onOpenSettings,
                      onPlay: () =>
                          ref.read(audioHandlerProvider).playTracks([featured]),
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            SliverToBoxAdapter(child: HomeHeaderRow(onShuffleAll: shuffleAll)),
            const SliverToBoxAdapter(child: SizedBox(height: 2)),
            const SliverToBoxAdapter(child: ScanBanner()),
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
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(28),
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
                              color: scheme.onSurfaceVariant,
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
/// app's name, and the ways into search and settings.
class _Header extends StatelessWidget {
  const _Header({required this.onOpenSearch, required this.onOpenSettings});

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.glassSolid, palette.background],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 16, 22),
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
              const SizedBox(width: 8),
              _RoundAction(
                icon: Icons.settings_rounded,
                label: 'Settings',
                onTap: onOpenSettings,
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
          width: 48,
          height: 48,
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
