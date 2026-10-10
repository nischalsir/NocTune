import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/layout/window_class.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/frosted.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/wave_bars.dart';
import '../../data/models/track.dart';
import '../playback/now_playing_screen.dart';

/// The cinematic header of the home screen: one featured track over its own
/// artwork. If that track is the one loaded in the player, the call to
/// action shows that it is playing; otherwise it offers to play it.
///
/// The scrim is dark in both themes, so the type on it is always white.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.track,
    required this.eyebrow,
    required this.isCurrent,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onPlay,
  });

  final Track track;
  final String eyebrow;

  /// Whether [track] is the one loaded in the player.
  final bool isCurrent;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onPlay;

  static const _ink = Color(0xFF07080C);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final wide = WindowClass.of(context) == WindowClass.expanded;
    final minHeight = (size.height * 0.54).clamp(340.0, 520.0);
    final artPath = track.artPath;

    Widget? art;
    if (artPath != null) {
      art = Image.file(
        File(artPath),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        // Decoded at display size, not the cover's full resolution.
        cacheWidth:
            (size.width *
                    (wide ? 0.62 : 1) *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: ColoredBox(
        color: _ink,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (art != null && wide)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: size.width * 0.62,
                // The artwork dissolves into the dark on its left edge.
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.transparent, Colors.white],
                    stops: [0, 0.5],
                  ).createShader(bounds),
                  child: art,
                ),
              )
            else if (art != null)
              Positioned.fill(child: art),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x99000000),
                      Color(0x26000000),
                      Color(0xB807080C),
                      Color(0xF207080C),
                    ],
                    stops: [0, 0.3, 0.64, 1],
                  ),
                ),
              ),
            ),
            // A minimum rather than a fixed height: with large accessibility
            // text the hero grows instead of clipping the title.
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Flexible(
                                  child: _SearchPill(onTap: onOpenSearch),
                                ),
                                const SizedBox(width: 8),
                                _SettingsButton(onTap: onOpenSettings),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Flush against the right margin. It shrinks rather
                          // than crowding out the search field when the text
                          // size is very large.
                          Expanded(
                            flex: 2,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'NOCTUNE',
                                  style: text.labelLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 40),
                            Text(
                              eyebrow,
                              style: text.labelSmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              track.title.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.displaySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              track.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.displayAlbum}\n${qualityLabel(track)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                color: Colors.white60,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (isCurrent)
                              const _NowPlayingPill()
                            else
                              _PlayPill(
                                semanticLabel: 'Play ${track.title}',
                                onTap: onPlay,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frosted search field at the top of the hero. It is a shortcut: tapping
/// it opens the Search destination.
class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: 'Search your library',
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Frosted(
          blurBackdrop: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Colors.white70,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Search tracks, artists, albums…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The frosted round button beside the search field that opens Settings.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Settings',
      excludeFromSemantics: true,
      child: Pressable(
        semanticLabel: 'Settings',
        onTap: onTap,
        child: const Frosted(
          blurBackdrop: true,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              Icons.settings_rounded,
              size: 20,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Play now": a frosted pill tinted with the accent.
class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.semanticLabel, required this.onTap});

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Frosted(
        tint: palette.accent,
        blurBackdrop: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Play now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: palette.onAccent),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: palette.onAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of "Play now" when the featured track is the one in the
/// player: moving sound bars and "Now playing" while it plays, still bars and
/// "Paused" otherwise. Tapping it opens the full player.
class _NowPlayingPill extends ConsumerWidget {
  const _NowPlayingPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final label = playing ? 'Now playing' : 'Paused';
    return Pressable(
      semanticLabel: '$label. Open player.',
      onTap: () => showNowPlaying(context),
      child: Frosted(
        blurBackdrop: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WaveBars(playing: playing, color: context.noc.accent),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
