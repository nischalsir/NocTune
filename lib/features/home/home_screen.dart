import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../library/scan/add_music_actions.dart';
import '../library/scan/scan_banner.dart';
import '../library/track_menu.dart';
import 'home_hero.dart';

/// Which tracks the home list shows.
enum FeedList {
  recent('Recent', Icons.schedule_rounded, 'Nothing played yet'),
  mostPlayed('Most played', Icons.trending_up_rounded, 'Nothing played yet'),
  added('Recently added', Icons.fiber_new_rounded, 'No tracks yet'),
  favourites('Favourites', Icons.favorite_rounded, 'No favourites yet');

  const FeedList(this.label, this.icon, this.emptyText);

  final String label;
  final IconData icon;
  final String emptyText;
}

/// The home feed: a hero featuring one track, a row of summary pills, a
/// statistics card with one headline number over three tiles, and a
/// switchable track list. Every number and row comes from the library on
/// this device.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  FeedList _list = FeedList.recent;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(libraryStatsProvider);
    final tracks = ref.watch(switch (_list) {
      FeedList.recent => recentlyPlayedProvider,
      FeedList.mostPlayed => mostPlayedProvider,
      FeedList.added => recentlyAddedProvider,
      FeedList.favourites => favoritesProvider,
    });
    final currentId = ref.watch(currentTrackIdProvider);
    final palette = context.noc;
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

    final rows = tracks.value ?? const <Track>[];
    // Favourites can be long; the feed shows the first of them and the
    // library holds the rest.
    final shown = rows.take(30).toList();

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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
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
                      onPlay: () =>
                          ref.read(audioHandlerProvider).playTracks([featured]),
                    ),
            ),
            SliverToBoxAdapter(
              child: _SummaryPills(stats: summary, onShuffleAll: shuffleAll),
            ),
            const SliverToBoxAdapter(child: ScanBanner()),
            SliverToBoxAdapter(
              child: _StatsCard(
                stats: summary,
                onOpenLibrary: widget.onOpenLibrary,
              ),
            ),
            // One card holding the list heading and its rows. Rows are built
            // lazily as they scroll into view.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: DecoratedSliver(
                decoration: BoxDecoration(
                  color: palette.glass,
                  borderRadius: BorderRadius.circular(30),
                ),
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _ListHeading(
                          selected: _list,
                          onSelected: (list) => setState(() => _list = list),
                        ),
                      ),
                      if (shown.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              tracks.isLoading ? 'Loading…' : _list.emptyText,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final track = shown[index];
                            return _FeedRow(
                              track: track,
                              isCurrent: track.id == currentId,
                              onTap: () => ref
                                  .read(audioHandlerProvider)
                                  .playTracks(shown, initialIndex: index),
                              onMenu: () => showTrackMenu(context, ref, track),
                            );
                          },
                        ),
                      if (rows.length > shown.length)
                        SliverToBoxAdapter(
                          child: TextButton(
                            onPressed: widget.onOpenLibrary,
                            child: Text('View all ${rows.length} in Library'),
                          ),
                        ),
                    ],
                  ),
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

/// The rounded header panel: the app's name and a way into search.
class _Header extends StatelessWidget {
  const _Header({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

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

/// Pills under the hero: how much music there is, and a button to shuffle
/// all of it.
class _SummaryPills extends StatelessWidget {
  const _SummaryPills({required this.stats, required this.onShuffleAll});

  final LibraryStats stats;
  final VoidCallback onShuffleAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 8,
        children: [
          _Pill(
            icon: Icons.headphones_rounded,
            text: '${formatLongDuration(stats.totalDuration)} on this device',
          ),
          Pressable(
            semanticLabel: 'Shuffle all tracks',
            onTap: onShuffleAll,
            child: const _Pill(
              icon: Icons.shuffle_rounded,
              text: 'Shuffle all',
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Frosted(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: palette.textPrimary),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The statistics card: plays as the headline number, then tracks, artists
/// and albums as three tiles.
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.onOpenLibrary});

  final LibraryStats stats;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.glass,
          borderRadius: BorderRadius.circular(34),
        ),
        child: Column(
          children: [
            Pressable(
              semanticLabel: '${stats.playCount} plays. Open your library.',
              onTap: onOpenLibrary,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.26),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatCount(stats.playCount),
                              style: text.displaySmall?.copyWith(fontSize: 42),
                            ),
                          ),
                          Text(
                            stats.playCount == 1 ? 'Play' : 'Plays',
                            style: text.titleSmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: palette.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatTile(value: stats.trackCount, label: 'Tracks'),
                const SizedBox(width: 10),
                _StatTile(value: stats.artistCount, label: 'Artists'),
                const SizedBox(width: 10),
                _StatTile(value: stats.albumCount, label: 'Albums'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatCount(value), style: text.titleLarge),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// "List" with a pill that switches what the list shows.
class _ListHeading extends StatelessWidget {
  const _ListHeading({required this.selected, required this.onSelected});

  final FeedList selected;
  final ValueChanged<FeedList> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 10),
      child: Row(
        children: [
          Expanded(child: Text('List', style: text.headlineSmall)),
          PopupMenuButton<FeedList>(
            tooltip: 'Choose what the list shows',
            onSelected: onSelected,
            itemBuilder: (context) => [
              for (final list in FeedList.values)
                CheckedPopupMenuItem(
                  value: list,
                  checked: list == selected,
                  child: Text(list.label),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
              decoration: BoxDecoration(
                color: palette.background.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(selected.icon, size: 18, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Text(selected.label, style: text.titleSmall),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A feed row: cover, title and artist, a "Now Playing" pill on the current
/// track, and the track's menu.
class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.track,
    required this.isCurrent,
    required this.onTap,
    required this.onMenu,
  });

  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Material(
      color: isCurrent
          ? palette.accent.withValues(alpha: 0.24)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 6, 7),
          child: Row(
            children: [
              Artwork(path: track.artPath, size: 54, radius: 14),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                // Gives way to the title rather than overflowing when text
                // is very large.
                Flexible(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Now Playing',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: palette.onAccent,
                      ),
                    ),
                  ),
                ),
              ],
              IconButton(
                tooltip: 'More for ${track.title}',
                onPressed: onMenu,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
