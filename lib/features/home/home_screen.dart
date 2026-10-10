import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/format.dart';
import '../../core/layout/window_class.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import '../library/scan/add_music_actions.dart';
import '../library/scan/scan_banner.dart';

/// The dashboard: a cinematic featured track over a row of glass cards, the
/// composition of the design reference with music in place of racing.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenLibrary,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider).value ?? const [];
    final mostPlayed = ref.watch(mostPlayedProvider).value ?? const [];
    final recentlyAdded = ref.watch(recentlyAddedProvider);
    final stats = ref.watch(libraryStatsProvider).value;

    return recentlyAdded.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load your library",
        message: '$error',
      ),
      data: (added) {
        if (added.isEmpty) {
          return SafeArea(
            child: Column(
              children: [
                const ScanBanner(),
                Expanded(
                  child: EmptyState(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Welcome to NocTune',
                    message:
                        Theme.of(context).platform == TargetPlatform.android
                        ? 'Scan this device to build your library. Your '
                              'music stays on the device.'
                        : 'Import audio files, or copy them into the NocTune '
                              'folder in the Files app, to build your library.',
                    action: const AddMusicActions(),
                  ),
                ),
              ],
            ),
          );
        }

        void play(List<Track> tracks, int index) => ref
            .read(audioHandlerProvider)
            .playTracks(tracks, initialIndex: index);

        final featured = recentlyPlayed.firstOrNull ?? added.first;
        final cards = <Widget>[
          if (mostPlayed.isNotEmpty)
            _DashCard(
              title: 'Most Played',
              footer: 'View full library',
              onFooter: onOpenLibrary,
              child: Column(
                children: [
                  for (final (index, track) in mostPlayed.take(4).indexed)
                    _RankRow(
                      rank: index + 1,
                      track: track,
                      onTap: () => play(mostPlayed, index),
                    ),
                ],
              ),
            ),
          if (recentlyPlayed.isNotEmpty)
            _DashCard(
              title: 'Recently Played',
              footer: 'View full library',
              onFooter: onOpenLibrary,
              child: Column(
                children: [
                  for (final (index, track) in recentlyPlayed.take(3).indexed)
                    _ThumbRow(
                      track: track,
                      onTap: () => play(recentlyPlayed, index),
                    ),
                ],
              ),
            ),
          _DashCard(
            title: 'Recently Added',
            footer: 'View all tracks',
            onFooter: onOpenLibrary,
            child: Column(
              children: [
                for (final (index, track) in added.take(3).indexed)
                  _ThumbRow(track: track, onTap: () => play(added, index)),
              ],
            ),
          ),
          if (stats != null) _LibraryCard(stats: stats),
        ];

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                track: featured,
                eyebrow: recentlyPlayed.isEmpty
                    ? 'RECENTLY ADDED'
                    : 'JUMP BACK IN',
                onOpenSearch: onOpenSearch,
                onPlay: () => play([featured], 0),
              ),
            ),
            const SliverToBoxAdapter(child: ScanBanner()),
            SliverToBoxAdapter(child: _CardGrid(cards: cards)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 24,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lays the cards out one per row on phones and side by side, at equal
/// height, on wider windows.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards});

  final List<Widget> cards;

  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final columns = switch (WindowClass.of(context)) {
      WindowClass.compact => 1,
      WindowClass.medium => 2,
      WindowClass.expanded => 3,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            children: [
              for (var start = 0; start < cards.length; start += columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: _gap),
                  child: columns == 1
                      ? cards[start]
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = start; i < start + columns; i++) ...[
                                if (i > start) const SizedBox(width: _gap),
                                Expanded(
                                  child: i < cards.length
                                      ? cards[i]
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cinematic header. On phones the artwork fills it and the type sits over a
/// dark scrim at the bottom; on wide windows the type is on the left and the
/// artwork bleeds in from the right, as in the design reference. The scrim is
/// dark in both themes, so the type on it is always white.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.track,
    required this.eyebrow,
    required this.onOpenSearch,
    required this.onPlay,
  });

  final Track track;
  final String eyebrow;
  final VoidCallback onOpenSearch;
  final VoidCallback onPlay;

  static const _ink = Color(0xFF07080C);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    final wide = WindowClass.of(context) == WindowClass.expanded;
    final minHeight = (size.height * (wide ? 0.56 : 0.54)).clamp(340.0, 520.0);
    final artPath = track.artPath;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    Widget? art;
    if (artPath != null) {
      art = Image.file(
        File(artPath),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        // Decoded at display size, not the cover's full resolution.
        cacheWidth: (size.width * (wide ? 0.62 : 1) * pixelRatio).round(),
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
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _SearchPill(onTap: onOpenSearch),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Shrinks rather than crowding out the search field
                          // when the text size is very large.
                          Flexible(
                            flex: 2,
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
                            _PlayPill(
                              label: 'Play now',
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

/// The glass search field at the top of the hero. It is a shortcut: tapping
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
        child: GlassPanel(
          radius: 24,
          blur: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
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
    );
  }
}

/// The accent call-to-action pill with a trailing arrow.
class _PlayPill extends StatelessWidget {
  const _PlayPill({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: [
              Color.lerp(palette.accent, Colors.black, 0.35)!,
              palette.accent,
            ],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
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
    );
  }
}

/// A glass dashboard card: a title, its content, and an accent link at the
/// bottom.
class _DashCard extends StatelessWidget {
  const _DashCard({
    required this.title,
    required this.child,
    this.footer,
    this.onFooter,
  });

  final String title;
  final Widget child;
  final String? footer;
  final VoidCallback? onFooter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassPanel(
      // Sits on the plain page background, so there is nothing to blur.
      blur: 0,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 10),
          child,
          if (footer != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onFooter,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: context.noc.accent,
                ),
                child: Text(footer!),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A numbered row for the Most Played card. The leader is highlighted.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.track,
    required this.onTap,
  });

  final int rank;
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Material(
      color: rank == 1 ? palette.glass : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('$rank', style: text.labelMedium),
              ),
              Artwork(path: track.artPath, size: 30, radius: 6),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${track.playCount} '
                '${track.playCount == 1 ? 'PLAY' : 'PLAYS'}',
                style: text.labelMedium?.copyWith(color: palette.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thumbnail row: cover with a play glyph, title and artist.
class _ThumbRow extends StatelessWidget {
  const _ThumbRow({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Artwork(path: track.artPath, size: 46, radius: 8),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x80000000),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
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

/// Library totals, closing on the listening time in bold with an accent
/// caption beneath it.
class _LibraryCard extends StatelessWidget {
  const _LibraryCard({required this.stats});

  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _DashCard(
      title: 'Your Library',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stat(value: '${stats.trackCount}', label: 'Tracks'),
              _Stat(value: '${stats.albumCount}', label: 'Albums'),
              _Stat(value: '${stats.artistCount}', label: 'Artists'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatLongDuration(stats.totalDuration).toUpperCase(),
            style: text.titleMedium,
          ),
          Text(
            'Of music, all on this device',
            style: text.bodyMedium?.copyWith(color: context.noc.accent),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.headlineSmall),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}
