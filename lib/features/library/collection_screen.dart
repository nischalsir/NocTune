import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/cover_accent.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/glass_circle.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'covers.dart';
import 'playlist_dialogs.dart';
import 'track_menu.dart';
import 'track_picker.dart';
import 'track_tile.dart';

/// One thing the page's own menu offers.
typedef _MenuItem = (IconData icon, String label, VoidCallback run);

/// A page for the tracks of one album, artist, genre, folder or playlist, or
/// for the favourites.
///
/// From the top: the collection's covers over a wash of the front one's
/// colour, its name with how many tracks it holds and how long they run,
/// Play and Shuffle, and the tracks. All of it scrolls as one list; the way
/// back and the page's own menu stay at the top.
class _CollectionPage extends ConsumerWidget {
  const _CollectionPage({
    required this.title,
    required this.tracks,
    required this.empty,
    this.playlistId,
    this.cover,
    this.menuTooltip = 'Options',
    this.menu = const [],
  });

  final String title;
  final AsyncValue<List<Track>> tracks;
  final Widget empty;
  final int? playlistId;

  /// A picture the user chose for this collection, which goes in front of
  /// its tracks' covers.
  final String? cover;
  final String menuTooltip;
  final List<_MenuItem> menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = tracks.value;
    // Up to three different covers: the user's choice, then the tracks' own
    // in the order they are listed.
    final covers = {
      ?cover,
      for (final track in loaded ?? const <Track>[]) ?track.artPath,
    }.take(3).toList();
    final currentId = ref.watch(currentTrackIdProvider);
    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.paddingOf(context);

    Future<void> play({required bool shuffled}) async {
      final handler = ref.read(audioHandlerProvider);
      await handler.playTracks(loaded!);
      await handler.setShuffleMode(
        shuffled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      );
    }

    return NocBackdrop(
      // Its own Material, so the page works on whichever navigator shows it.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (covers.isNotEmpty)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: screen.height * 0.62,
                child: _CoverWash(path: covers.first),
              ),
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    title: title,
                    tracks: loaded,
                    covers: covers,
                    onPlay: () => play(shuffled: false),
                    onShuffle: () => play(shuffled: true),
                  ),
                ),
                ...tracks.when(
                  loading: () => const [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                  error: (error, _) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: "Couldn't load these tracks",
                        message: '$error',
                      ),
                    ),
                  ],
                  data: (tracks) => [
                    if (tracks.isEmpty)
                      SliverFillRemaining(hasScrollBody: false, child: empty)
                    else
                      SliverFixedExtentList.builder(
                        itemExtent: 64,
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return TrackTile(
                            track: track,
                            isCurrent: track.id == currentId,
                            onTap: () => ref
                                .read(audioHandlerProvider)
                                .playTracks(tracks, initialIndex: index),
                            onMenu: () => showTrackMenu(
                              context,
                              ref,
                              track,
                              playlistId: playlistId,
                            ),
                          );
                        },
                      ),
                  ],
                ),
                // Clear of the navigation bar and mini-player over the page.
                SliverToBoxAdapter(child: SizedBox(height: inset.bottom + 16)),
              ],
            ),
            Positioned(
              top: inset.top + 8,
              left: math.max(16, inset.left),
              right: math.max(16, inset.right),
              child: Row(
                children: [
                  Tooltip(
                    message: 'Back',
                    excludeFromSemantics: true,
                    child: Pressable(
                      semanticLabel: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const GlassCircle(
                        Icons.arrow_back_ios_new_rounded,
                        blurBackdrop: true,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (menu.isNotEmpty)
                    PopupMenuButton<VoidCallback>(
                      tooltip: menuTooltip,
                      onSelected: (run) => run(),
                      itemBuilder: (context) => [
                        for (final (icon, label, run) in menu)
                          PopupMenuItem(
                            value: run,
                            height: 40,
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      child: const GlassCircle(
                        Icons.more_horiz_rounded,
                        blurBackdrop: true,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The covers, the name and its details, and Play and Shuffle.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.tracks,
    required this.covers,
    required this.onPlay,
    required this.onShuffle,
  });

  final String title;

  /// Null until the tracks have been read.
  final List<Track>? tracks;
  final List<String> covers;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final tracks = this.tracks;
    final width = MediaQuery.sizeOf(context).width;

    String? details;
    if (tracks != null) {
      details = '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}';
      if (tracks.isNotEmpty) {
        final length = tracks.fold(
          Duration.zero,
          (total, track) => total + track.duration,
        );
        details = '$details · ${formatLongDuration(length)}';
      }
    }

    return Padding(
      // Below the buttons that stay at the top of the page.
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 84),
      child: Column(
        children: [
          _CoverFan(covers: covers, size: (width * 0.68).clamp(150.0, 300.0)),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (details != null) ...[
            const SizedBox(height: 4),
            Text(
              details,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ],
          if (tracks != null && tracks.isNotEmpty) ...[
            const SizedBox(height: 22),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 452),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _PillButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        filled: true,
                        onTap: onPlay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PillButton(
                        icon: Icons.shuffle_rounded,
                        label: 'Shuffle',
                        onTap: onShuffle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// The first cover in front and, when there are three, the other two
/// leaning out from behind it like cards held in a hand. With only two the
/// second would lean out on one side alone, so it is left out.
class _CoverFan extends StatelessWidget {
  const _CoverFan({required this.covers, required this.size});

  final List<String> covers;

  /// The side of the cover in front.
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    // [side] is -1 for the cover leaning out to the left, 1 to the right.
    Widget behind(String path, int side) => Transform.translate(
      offset: Offset(side * size * 0.29, 0),
      child: Transform.rotate(
        angle: side * math.pi / 20,
        child: DecoratedBox(
          // Dimmed, so it sits back from the cover in front.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(size * 0.06),
          ),
          child: Artwork(path: path, size: size * 0.65, radius: size * 0.06),
        ),
      ),
    );

    return ExcludeSemantics(
      child: SizedBox(
        key: const ValueKey('collection-covers'),
        height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (covers.length > 2) ...[
              behind(covers[2], -1),
              behind(covers[1], 1),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.09),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.45 : 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Artwork(
                path: covers.firstOrNull,
                size: size,
                radius: size * 0.09,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wide pill with an icon and a word: filled for the main action, glass
/// for the other.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final color = filled ? palette.background : palette.textPrimary;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Shrinks rather than overflowing when the text is very large.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: filled
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: palette.textPrimary,
                shape: const StadiumBorder(),
              ),
              child: content,
            )
          : Frosted(child: content),
    );
  }
}

/// The page's colour: the main colour of the cover in front, strongest at
/// the top and fading out downwards. It comes in softly once the cover has
/// been read; a cover with no colour to speak of leaves the page as it is.
class _CoverWash extends ConsumerWidget {
  const _CoverWash({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final seed = ref.watch(coverSeedProvider(path)).value;
    var color = Colors.transparent;
    if (seed != null) {
      final hsl = HSLColor.fromColor(seed);
      // Deep enough in the dark theme, and pale enough in the light one,
      // for the text on it to stay readable whatever the cover is.
      color = hsl
          .withSaturation(math.max(hsl.saturation, 0.5))
          .withLightness(dark ? 0.3 : 0.8)
          .toColor();
    }
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: seed == null ? 0 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.9),
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0),
              ],
              stops: const [0, 0.45, 1],
            ),
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

/// The tracks the user has favourited, under a cover they can choose.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(favouritesCoverProvider);

    Future<void> setCover(String? path) async {
      ref.read(favouritesCoverProvider.notifier).set(path);
      await ref.read(coverStoreProvider).discard(cover);
    }

    return _CollectionPage(
      title: 'Favourites',
      cover: cover,
      tracks: ref.watch(favoritesProvider),
      empty: const EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'No favourites yet',
        message: 'Tap the heart on a track you love to keep it here.',
      ),
      menuTooltip: 'Favourites options',
      menu: [
        (
          Icons.image_outlined,
          'Change cover',
          () async {
            final picked = await ref.read(coverStoreProvider).pick();
            if (picked != null) await setCover(picked);
          },
        ),
        if (cover != null)
          (Icons.hide_image_outlined, 'Remove cover', () => setCover(null)),
      ],
    );
  }
}

/// One playlist: an album of the user's own making, with tracks they pick
/// and a cover they can choose.
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(libraryRepositoryProvider);
    // Follow renames and cover changes made from this screen.
    final current =
        ref
            .watch(playlistsProvider)
            .value
            ?.where((candidate) => candidate.id == playlist.id)
            .firstOrNull ??
        playlist;
    final tracks = ref.watch(playlistTracksProvider(playlist.id));

    Future<void> addTracks() async {
      final chosen = await showTrackPicker(
        context,
        alreadyIn: {for (final track in tracks.value ?? const []) track.id},
      );
      if (chosen != null) {
        await repository.addTracksToPlaylist(current.id, chosen);
      }
    }

    Future<void> setCover(String? path) async {
      await repository.setPlaylistCover(current.id, path);
      await ref.read(coverStoreProvider).discard(current.coverPath);
    }

    return _CollectionPage(
      title: current.name,
      playlistId: playlist.id,
      cover: current.coverPath,
      tracks: tracks,
      empty: EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'This playlist is empty',
        message: 'Pick the tracks that belong in it.',
        action: FilledButton.icon(
          onPressed: addTracks,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add tracks'),
        ),
      ),
      menuTooltip: 'Playlist options',
      menu: [
        (Icons.add_rounded, 'Add tracks', addTracks),
        (
          Icons.image_outlined,
          'Change cover',
          () async {
            final picked = await ref.read(coverStoreProvider).pick();
            if (picked != null) await setCover(picked);
          },
        ),
        if (current.coverPath != null)
          (Icons.hide_image_outlined, 'Remove cover', () => setCover(null)),
        (
          Icons.edit_outlined,
          'Rename',
          () async {
            final name = await askPlaylistName(
              context,
              initialName: current.name,
            );
            if (name != null) {
              await repository.renamePlaylist(current.id, name);
            }
          },
        ),
        (
          Icons.delete_outline_rounded,
          'Delete playlist',
          () async {
            if (!await _confirmDelete(context, current.name)) return;
            await repository.deletePlaylist(current.id);
            await ref.read(coverStoreProvider).discard(current.coverPath);
            if (context.mounted) Navigator.of(context).pop();
          },
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
