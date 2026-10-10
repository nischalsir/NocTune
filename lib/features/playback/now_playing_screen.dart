import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/track.dart';
import '../library/track_menu.dart';
import '../lyrics/lyrics_view.dart';
import 'format_badges.dart';
import 'now_playing_route.dart';
import 'queue_sheet.dart';
import 'transport_controls.dart';

/// Opens the full player over the whole app.
Future<void> showNowPlaying(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(NowPlayingRoute(child: const NowPlayingScreen()));

/// The immersive player: header buttons, a large rounded cover, the title
/// over an artist chip, a thick scrubber, three transport buttons and a row
/// of secondary controls, all in round frosted glass. The cover area turns
/// into the lyrics view and back.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).value;
    final palette = context.noc;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The wash cross-fades as the cover changes between tracks.
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 500),
            child: _ArtworkWash(
              key: ValueKey(item?.artUri),
              path: item?.artUri?.toFilePath(),
            ),
          ),
          SafeArea(
            child: item == null
                ? const Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: _Header(item: null),
                      ),
                      Expanded(
                        child: EmptyState(
                          icon: Icons.music_off_outlined,
                          title: 'Nothing is playing',
                          message: 'Pick a track from your library to start.',
                        ),
                      ),
                    ],
                  )
                : _PlayerLayout(
                    item: item,
                    showLyrics: _showLyrics,
                    onToggleLyrics: () =>
                        setState(() => _showLyrics = !_showLyrics),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The artwork, heavily blurred and veiled with the page colour, so the
/// player takes on the mood of the cover while text stays legible in both
/// themes.
class _ArtworkWash extends StatelessWidget {
  const _ArtworkWash({super.key, required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final path = this.path;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (path != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              // Blurred beyond recognition, so a tiny decode is plenty.
              cacheWidth: 64,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.background.withValues(alpha: 0.62),
                palette.background.withValues(alpha: 0.95),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerLayout extends ConsumerWidget {
  const _PlayerLayout({
    required this.item,
    required this.showLyrics,
    required this.onToggleLyrics,
  });

  final MediaItem item;
  final bool showLyrics;
  final VoidCallback onToggleLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The library's record of this track, ignored while it still belongs to
    // the previous one.
    final currentId = ref.watch(currentTrackIdProvider);
    final loaded = ref.watch(currentTrackProvider).value;
    final track = loaded != null && loaded.id == currentId ? loaded : null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Cover or lyrics, cross-fading in the same space.
    Widget stage(double width, double height) => SizedBox(
      width: width,
      height: height,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: showLyrics && track != null
            ? LyricsView(key: const ValueKey('lyrics'), track: track)
            : Center(
                key: const ValueKey('cover'),
                child: _HeroArtwork(
                  path: item.artUri?.toFilePath(),
                  size: min(width, height),
                ),
              ),
      ),
    );

    final details = _Details(
      item: item,
      track: track,
      showLyrics: showLyrics,
      onToggleLyrics: onToggleLyrics,
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Short and wide (a phone on its side): cover beside the controls.
        if (box.maxHeight < 520 && box.maxWidth > box.maxHeight) {
          final side = box.maxHeight - 24;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                stage(showLyrics ? box.maxWidth * 0.42 : side, side),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _Header(item: item, track: track),
                        const SizedBox(height: 8),
                        details,
                        const SizedBox(height: 6),
                        SeekBar(
                          duration: item.duration ?? Duration.zero,
                          inline: true,
                        ),
                        const FormatBadges(),
                        const SizedBox(height: 6),
                        const PrimaryTransport(dense: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final side = box.maxWidth < 360 ? 16.0 : 24.0;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final contentWidth = min(box.maxWidth, 560.0) - side * 2;
        // With lyrics open the secondary row steps aside to give them room.
        final reserved = (showLyrics ? 330 : 420) + 70 * textScale;
        final stageHeight = (box.maxHeight - reserved).clamp(
          150.0,
          showLyrics ? 900.0 : contentWidth,
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side, 4, side, 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Header(item: item, track: track),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: stage(contentWidth, stageHeight),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          SeekBar(duration: item.duration ?? Duration.zero),
                          const SizedBox(height: 6),
                          // Directly above Play/Pause, as the label for what
                          // that button plays.
                          const FormatBadges(),
                          const SizedBox(height: 10),
                          const PrimaryTransport(),
                          if (!showLyrics) ...[
                            const SizedBox(height: 18),
                            const _SecondaryRow(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.item, this.track});

  final MediaItem? item;
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final track = this.track;
    return Row(
      children: [
        GlassButton(
          icon: Icons.keyboard_arrow_down_rounded,
          label: 'Close player',
          iconSize: 28,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('NOW PLAYING', style: text.labelSmall),
              if (item?.album case final album?)
                Text(
                  album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
            ],
          ),
        ),
        // Keeps the title centred when there is no track to act on.
        if (track == null)
          const SizedBox(width: 48)
        else
          GlassButton(
            icon: Icons.more_vert_rounded,
            label: 'More for this track',
            onTap: () => showTrackMenu(context, ref, track),
          ),
      ],
    );
  }
}

/// The cover. It flies in from the mini-player, settles back slightly while
/// paused, and cross-fades when the track changes. With reduced motion on it
/// simply stays put.
class _HeroArtwork extends ConsumerWidget {
  const _HeroArtwork({required this.path, required this.size});

  final String? path;
  final double size;

  static const _radius = 34.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: playing || reduceMotion ? 1 : 0.92,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 36,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Hero(
          tag: kNowPlayingArtworkHero,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 350),
            child: Artwork(
              key: ValueKey(path),
              path: path,
              size: size,
              radius: _radius,
            ),
          ),
        ),
      ),
    );
  }
}

/// Title over the artist chip, with favourite and lyrics beside them.
class _Details extends ConsumerWidget {
  const _Details({
    required this.item,
    required this.track,
    required this.showLyrics,
    required this.onToggleLyrics,
  });

  final MediaItem item;
  final Track? track;
  final bool showLyrics;
  final VoidCallback onToggleLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final track = this.track;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // Title and artist fade over to the next track's.
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: Column(
              key: ValueKey(item.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.glass,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.artist ?? 'Unknown artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (track != null) ...[
          const SizedBox(width: 10),
          GlassButton(
            icon: track.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: track.isFavorite
                ? 'Remove from favourites'
                : 'Add to favourites',
            selected: track.isFavorite,
            onTap: () => ref
                .read(libraryRepositoryProvider)
                .setFavorite(track.id, favorite: !track.isFavorite),
          ),
          const SizedBox(width: 8),
          GlassButton(
            icon: Icons.lyrics_rounded,
            label: showLyrics ? 'Hide lyrics' : 'Show lyrics',
            selected: showLyrics,
            onTap: onToggleLyrics,
          ),
        ],
      ],
    );
  }
}

/// Shuffle, queue and repeat, as three frosted pills.
class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Row(
      children: [
        const Expanded(child: ShuffleButton()),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Pressable(
            semanticLabel: 'Queue',
            onTap: () => showQueueSheet(context),
            child: SizedBox(
              height: 52,
              child: Frosted(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.queue_music_rounded, color: palette.textPrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Queue',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: RepeatButton()),
      ],
    );
  }
}
