import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'playlist_dialogs.dart';
import 'track_menu.dart';
import 'track_tile.dart';

/// A page for the tracks of one album, artist, genre, folder or playlist.
///
/// From the top: the collection's covers fanned out over a wash of the
/// first one's colours, its name with how many tracks it holds and how long
/// they run, Play and Shuffle, and the tracks. All of it scrolls as one
/// list; the way back and the page's own actions stay at the top.
class _CollectionPage extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = tracks.value;
    // Up to three different covers, the first track's in front.
    final covers = {
      for (final track in loaded ?? const <Track>[]) ?track.artPath,
    }.take(3).toList();
    final currentId = ref.watch(currentTrackIdProvider);
    final screen = MediaQuery.sizeOf(context);
    final inset = MediaQuery.paddingOf(context);
    // A whole number of pixels: an edge that falls part-way through one
    // leaves a hairline across the page where the wash has faded out.
    final pixels = MediaQuery.devicePixelRatioOf(context);
    final washHeight = (screen.height * 0.62 * pixels).roundToDouble() / pixels;

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
                height: washHeight,
                child: _CoverWash(
                  key: ValueKey(covers.first),
                  path: covers.first,
                ),
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
                      child: const _GlassCircle(
                        Icons.arrow_back_ios_new_rounded,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ...actions,
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

/// The first cover in front, with up to two more leaning out from behind
/// it like cards held in a hand.
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
            if (covers.length > 2) behind(covers[2], -1),
            if (covers.length > 1) behind(covers[1], 1),
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

/// A round glass button for the top of the page. It blurs what is behind
/// it, because the covers and the list scroll underneath.
class _GlassCircle extends StatelessWidget {
  const _GlassCircle(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Frosted(
      blurBackdrop: true,
      child: SizedBox.square(
        dimension: 44,
        child: Icon(icon, size: 20, color: context.noc.textPrimary),
      ),
    );
  }
}

/// The page's colour: the cover, blurred past recognition and veiled
/// towards the page behind it, fading out downwards.
///
/// It does not move, so it is drawn once and kept as a picture. Otherwise
/// the blur would be worked out again on every frame the list scrolls.
class _CoverWash extends StatefulWidget {
  const _CoverWash({super.key, required this.path});

  final String path;

  @override
  State<_CoverWash> createState() => _CoverWashState();
}

class _CoverWashState extends State<_CoverWash> {
  final _picture = SnapshotController(allowSnapshotting: true);
  bool _coverDrawn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The veil takes the theme's page colour: draw again when it changes.
    _picture.clear();
  }

  @override
  void dispose() {
    _picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: SnapshotWidget(
        controller: _picture,
        // Drawn again at the new size when the window changes.
        autoresize: true,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.transparent],
            stops: [0.2, 1],
          ).createShader(bounds),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 40,
                  sigmaY: 40,
                  tileMode: TileMode.clamp,
                ),
                child: Image.file(
                  File(widget.path),
                  fit: BoxFit.cover,
                  // Blurred beyond recognition, so a tiny decode is plenty.
                  cacheWidth: 64,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  frameBuilder: (context, child, frame, _) {
                    // The picture was taken before the cover had loaded.
                    if (frame != null && !_coverDrawn) {
                      _coverDrawn = true;
                      _picture.clear();
                    }
                    return child;
                  },
                ),
              ),
              // Keeps the text on it readable whatever the cover is.
              ColoredBox(
                color: context.noc.background.withValues(
                  alpha: dark ? 0.5 : 0.6,
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
          child: const _GlassCircle(Icons.more_horiz_rounded),
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
