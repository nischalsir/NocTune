import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import 'now_playing_route.dart';
import 'queue_sheet.dart';
import 'transport_controls.dart';

/// Opens the full player over the whole app.
Future<void> showNowPlaying(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(NowPlayingRoute(child: const NowPlayingScreen()));

/// The immersive player: artwork, track details, seeking and transport.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      _Header(),
                      Expanded(
                        child: EmptyState(
                          icon: Icons.music_off_outlined,
                          title: 'Nothing is playing',
                          message: 'Pick a track from your library to start.',
                        ),
                      ),
                    ],
                  )
                : _PlayerLayout(item: item),
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
                palette.background.withValues(alpha: 0.55),
                palette.background.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerLayout extends StatelessWidget {
  const _PlayerLayout({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final artPath = item.artUri?.toFilePath();
        // Short and wide (a phone on its side): artwork beside the controls.
        if (box.maxHeight < 520 && box.maxWidth > box.maxHeight) {
          final artSize = box.maxHeight - 48;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                _HeroArtwork(path: artPath, size: artSize),
                const SizedBox(width: 28),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const _Header(),
                        _Controls(item: item),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Artwork takes whatever height the controls leave, within limits, so
        // the same layout fits a small phone and a tablet.
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final reserved = 250 + 110 * textScale;
        final side = box.maxWidth < 360 ? 16.0 : 24.0;
        final artSize = min(
          box.maxWidth - 56,
          box.maxHeight - reserved,
        ).clamp(140.0, 460.0);
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  // The five transport buttons need the room on narrow phones.
                  padding: EdgeInsets.fromLTRB(side, 4, side, 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _Header(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _HeroArtwork(path: artPath, size: artSize),
                      ),
                      _Controls(item: item),
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Close player',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        ),
        Expanded(
          child: Text(
            'NOW PLAYING',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        IconButton(
          tooltip: 'Queue',
          onPressed: () => showQueueSheet(context),
          icon: const Icon(Icons.queue_music_rounded),
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
          borderRadius: BorderRadius.circular(22),
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
              radius: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              // Title and artist fade over to the next track's.
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(item.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [item.artist, item.album].nonNulls.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            if (track != null)
              IconButton(
                tooltip: track.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                onPressed: () => ref
                    .read(libraryRepositoryProvider)
                    .setFavorite(track.id, favorite: !track.isFavorite),
                color: track.isFavorite ? palette.accent : null,
                icon: Icon(
                  track.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
          ],
        ),
        if (track != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              qualityLabel(track).toUpperCase(),
              style: text.labelSmall?.copyWith(color: palette.textTertiary),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SeekBar(duration: item.duration ?? Duration.zero),
        const SizedBox(height: 4),
        const TransportControls(),
      ],
    );
  }
}
