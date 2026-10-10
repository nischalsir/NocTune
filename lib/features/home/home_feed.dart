import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/wave_bars.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';
import 'home_rows.dart';

// The pieces of the home feed below the hero: the pill row, the statistics
// card and the list with its sort menu. Sizes, radii and colour roles are
// fixed by the design; colours come from the theme's tonal scheme.

const _pillRadius = BorderRadius.all(Radius.circular(999));
const _artworkRadius = 12.0;
// Rows sit 8 inside a container of radius 28, so their own radius is 20:
// the two curves stay parallel.
const _rowRadius = BorderRadius.all(Radius.circular(20));
const _nowPlayingRadius = _rowRadius;

/// The row under the hero: an action pill on the left and the listening
/// time on the right.
class HomeHeaderRow extends StatelessWidget {
  const HomeHeaderRow({super.key, required this.onShuffleAll});

  final VoidCallback onShuffleAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Semantics(
              button: true,
              label: 'Shuffle all tracks',
              excludeSemantics: true,
              child: Material(
                color: context.feedPanel,
                shape: StadiumBorder(side: context.feedRim),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onShuffleAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shuffle, size: 14, color: scheme.onSurface),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Shuffle all',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlexType.labelLarge.copyWith(
                              fontSize: 13,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Flexible(child: ListenTimerPill()),
        ],
      ),
    );
  }
}

/// Estimated time spent listening in this app, counting up while music
/// plays: every finished play at the track's full length, plus how far into
/// the current track the player is.
class ListenTimerPill extends ConsumerWidget {
  const ListenTimerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    var listened =
        ref.watch(libraryStatsProvider).value?.listenedDuration ??
        Duration.zero;
    final current = ref.watch(currentTrackProvider).value;
    if (current != null &&
        current.id == ref.watch(currentTrackIdProvider) &&
        current.playCount > 0) {
      // The current play is already in the total at full length; swap that
      // for the position actually reached.
      final seconds = ref.watch(
        playbackPositionProvider.select((p) => p.value?.inSeconds ?? 0),
      );
      listened =
          listened -
          current.duration +
          Duration(seconds: math.min(seconds, current.duration.inSeconds));
    }
    final text = formatListeningTime(listened.inSeconds);
    final color = isPlaying ? scheme.primary : scheme.onSurface;

    return Semantics(
      label: 'Estimated listening time: $text',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Estimated listening time',
        child: Material(
          color: context.feedPanel,
          shape: StadiumBorder(side: context.feedRim),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.headset,
                  size: 16,
                  color: isPlaying ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlexType.labelLarge.copyWith(
                      fontSize: 13,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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

/// The statistics card: plays as the headline number with a way into the
/// library, then tracks, artists and albums as three tiles. It fades and
/// unfolds in once, and its numbers count up to their values.
class HomeStatsCard extends StatefulWidget {
  const HomeStatsCard({
    super.key,
    required this.stats,
    required this.onOpenLibrary,
  });

  final LibraryStats stats;
  final VoidCallback onOpenLibrary;

  @override
  State<HomeStatsCard> createState() => _HomeStatsCardState();
}

class _HomeStatsCardState extends State<HomeStatsCard>
    with SingleTickerProviderStateMixin {
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = widget.stats;
    final onContainer = scheme.onPrimaryContainer;

    // The panels inside sit 12 in from the card's edge, so their radius is
    // the card's less 12 and the corners stay concentric.
    final card = Material(
      color: context.feedPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: context.feedRim,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Material(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      // Keeps a very long number clear of the arrow.
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: Semantics(
                        label: '${stats.playCount} plays',
                        excludeSemantics: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _AnimatedCount(
                                value: stats.playCount,
                                style: FlexType.displaySmall.copyWith(
                                  color: onContainer,
                                ),
                              ),
                            ),
                            Text(
                              'Plays',
                              style: FlexType.labelMedium.copyWith(
                                color: onContainer.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox.square(
                        dimension: 40,
                        child: IconButton(
                          tooltip: 'Open library',
                          onPressed: widget.onOpenLibrary,
                          padding: EdgeInsets.zero,
                          iconSize: 22,
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                          ),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatPill(label: 'Tracks', value: stats.trackCount),
                const SizedBox(width: 8),
                _StatPill(label: 'Artists', value: stats.artistCount),
                const SizedBox(width: 8),
                _StatPill(label: 'Albums', value: stats.albumCount),
              ],
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FadeTransition(
        opacity: _enter,
        child: SizeTransition(
          sizeFactor: _enter,
          alignment: Alignment.bottomCenter,
          child: card,
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: context.feedInset,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _AnimatedCount(
                  value: value,
                  style: FlexType.titleMedium.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlexType.labelSmall.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number that springs up to [value] from wherever it currently is. Zero
/// is shown as a dash.
class _AnimatedCount extends StatefulWidget {
  const _AnimatedCount({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  State<_AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<_AnimatedCount>
    with SingleTickerProviderStateMixin {
  // A soft spring with a little overshoot.
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 50,
    ratio: 0.5,
  );

  late final _count = AnimationController.unbounded(vsync: this);
  int? _target;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(_AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animate();
  }

  void _animate() {
    if (_target == widget.value) return;
    _target = widget.value;
    final target = widget.value.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _count.value = target;
    } else {
      _count.animateWith(SpringSimulation(_spring, _count.value, target, 0));
    }
  }

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _count,
      builder: (context, _) {
        final shown = _count.value.truncate();
        return Text(
          shown <= 0 ? '—' : formatCount(shown),
          maxLines: 1,
          style: widget.style,
        );
      },
    );
  }
}

/// "List" and the pill that chooses what the list shows.
class HomeListHeader extends StatefulWidget {
  const HomeListHeader({
    super.key,
    required this.sort,
    required this.onSortChanged,
  });

  final HomeSort sort;
  final ValueChanged<HomeSort> onSortChanged;

  @override
  State<HomeListHeader> createState() => _HomeListHeaderState();
}

class _HomeListHeaderState extends State<HomeListHeader> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed == _pressed) return;
    // Felt the instant the finger lands, before the menu covers the pill.
    if (pressed) HapticFeedback.vibrate();
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'List',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlexType.titleLarge.copyWith(color: scheme.onSurface),
            ),
          ),
          PopupMenuButton<HomeSort>(
            tooltip: 'Choose what the list shows',
            position: PopupMenuPosition.under,
            color: context.feedMenu,
            surfaceTintColor: Colors.transparent,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            menuPadding: const EdgeInsets.symmetric(vertical: 12),
            onSelected: (sort) {
              HapticFeedback.vibrate();
              widget.onSortChanged(sort);
            },
            itemBuilder: (context) => [
              for (final sort in HomeSort.values)
                PopupMenuItem(
                  value: sort,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _SortOption(sort: sort, active: sort == widget.sort),
                ),
            ],
            child: Listener(
              onPointerDown: (_) => _setPressed(true),
              onPointerUp: (_) => _setPressed(false),
              onPointerCancel: (_) => _setPressed(false),
              child: AnimatedScale(
                scale: _pressed && !reduceMotion ? 0.9 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.feedChip,
                    borderRadius: _pillRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.sort.icon,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.sort.label,
                        maxLines: 1,
                        style: FlexType.labelLarge.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_more,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({required this.sort, required this.active});

  final HomeSort sort;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40, minWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: active
          ? BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Row(
        children: [
          Icon(
            sort.icon,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              sort.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (active ? FlexType.titleMedium : FlexType.bodyLarge)
                  .copyWith(
                    fontSize: 16,
                    color: active ? scheme.primary : scheme.onSurface,
                  ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 12),
            Icon(Icons.check, color: scheme.primary),
          ],
        ],
      ),
    );
  }
}

/// A day label between groups of plays.
class HomeDateHeader extends StatelessWidget {
  const HomeDateHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: FlexType.labelMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A track in the home list: cover, title and artist, then a "Now Playing"
/// pill on the track in the player, a count badge, and the track's menu.
class HomeTrackRow extends StatelessWidget {
  const HomeTrackRow({
    super.key,
    required this.track,
    required this.isNowPlaying,
    required this.isPlaying,
    required this.onTap,
    required this.onMenu,
    this.badge,
  });

  final Track track;
  final String? badge;

  /// Whether this is the track loaded in the player.
  final bool isNowPlaying;

  /// Whether audio is running, which is what makes the row's motion run.
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = this.badge;

    Widget row = Material(
      type: MaterialType.transparency,
      borderRadius: isNowPlaying ? _nowPlayingRadius : _rowRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onMenu,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 52,
                  child: Stack(
                    children: [
                      Artwork(
                        path: track.artPath,
                        size: 52,
                        radius: _artworkRadius,
                      ),
                      if (isNowPlaying)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: _pillRadius,
                            ),
                            child: WaveBars(
                              playing: isPlaying,
                              color: scheme.onPrimaryContainer,
                              size: const Size(16, 12),
                              barCount: 3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlexType.titleMedium.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlexType.bodyMedium.copyWith(
                          color: isNowPlaying
                              ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Shown whole; it is only cut short when the text is so
                // large that it would otherwise push the row past its edge.
                if (isNowPlaying)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.36,
                    ),
                    child: _NowPlayingPill(playing: isPlaying),
                  ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.feedChip,
                      borderRadius: _pillRadius,
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      style: FlexType.labelMedium.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                _OverflowButton(
                  label: 'More for ${track.title}',
                  onTap: onMenu,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isNowPlaying) {
      row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _nowPlayingRadius,
            gradient: LinearGradient(
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.70),
                context.feedPanel.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: row,
        ),
      );
    }
    return row;
  }
}

/// "Now Playing" with a breathing dot; still, and reading "Paused", while
/// playback is paused.
class _NowPlayingPill extends StatefulWidget {
  const _NowPlayingPill({required this.playing});

  final bool playing;

  @override
  State<_NowPlayingPill> createState() => _NowPlayingPillState();
}

class _NowPlayingPillState extends State<_NowPlayingPill>
    with TickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final _dot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_NowPlayingPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final animate = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (animate == _pulse.isAnimating) return;
    if (animate) {
      _pulse.repeat(reverse: true);
      _dot.repeat(reverse: true);
    } else {
      _pulse.stop();
      _dot.stop();
      _pulse.value = 0;
      _dot.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _dot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.06).animate(_pulse),
      child: Material(
        color: scheme.primary,
        elevation: 2,
        borderRadius: _pillRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: Tween(begin: 0.45, end: 1.0).animate(_dot),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.playing ? 'Now Playing' : 'Paused',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlexType.labelSmall.copyWith(color: scheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small tonal squircle that opens a track's menu.
class _OverflowButton extends StatelessWidget {
  const _OverflowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        // The drawn button is small; the area that takes the tap is not.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 26,
                height: 32,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    context.feedPanel,
                    scheme.primaryContainer,
                    0.55,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An album or artist in the "Top" lists. Artists get a round picture.
class HomeGroupRow extends StatelessWidget {
  const HomeGroupRow({
    super.key,
    required this.group,
    required this.isArtist,
    required this.onTap,
  });

  final TrackGroupSummary group;
  final bool isArtist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artist = isArtist ? null : group.artist;
    return Material(
      type: MaterialType.transparency,
      borderRadius: _rowRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              children: [
                Artwork(
                  path: group.artPath,
                  size: 52,
                  radius: isArtist ? 26 : _artworkRadius,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlexType.titleMedium.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      if (artist != null && artist.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FlexType.bodyMedium.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
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

/// One thing on a shelf: a cover with a title and a line under it.
typedef ShelfItem = ({
  String? artPath,
  String title,
  String? subtitle,
  VoidCallback onTap,
});

/// A titled row of covers that scrolls sideways, such as the newest albums
/// or the favourite tracks.
class HomeShelf extends StatelessWidget {
  const HomeShelf({
    super.key,
    required this.title,
    required this.items,
    required this.onSeeAll,
  });

  final String title;
  final List<ShelfItem> items;
  final VoidCallback onSeeAll;

  static const _cover = 116.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlexType.titleLarge.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                child: Text('See all', style: FlexType.labelLarge),
              ),
            ],
          ),
        ),
        SizedBox(
          // The cover, then two lines of text at the size the user reads.
          height: _cover + 8 + scaler.scale(20) + scaler.scale(18) + 6,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final subtitle = item.subtitle;
              return Semantics(
                button: true,
                label: [item.title, ?subtitle].join(', '),
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: item.onTap,
                  child: SizedBox(
                    width: _cover,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Artwork(path: item.artPath, size: _cover, radius: 16),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FlexType.titleSmall.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlexType.bodySmall.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The feed's surfaces. In the dark theme they are tonal fills taken from
/// the accent. In the light theme they are white glass with a hairline rim,
/// so the page's backdrop shows softly through them.
extension FeedSurfaces on BuildContext {
  bool get _lightFeed => Theme.of(this).brightness == Brightness.light;
  ColorScheme get _feedScheme => Theme.of(this).colorScheme;

  /// A large container, such as the list.
  Color get feedCard => _lightFeed
      ? Colors.white.withValues(alpha: 0.62)
      : _feedScheme.surfaceContainer;

  /// A card or pill standing on the page.
  Color get feedPanel => _lightFeed
      ? Colors.white.withValues(alpha: 0.72)
      : _feedScheme.surfaceContainerHigh;

  /// A small control on a card.
  Color get feedChip => _lightFeed
      ? Colors.white.withValues(alpha: 0.9)
      : _feedScheme.surfaceContainerHighest;

  /// A tile set into a card.
  Color get feedInset => _lightFeed
      ? Colors.white.withValues(alpha: 0.7)
      : _feedScheme.surface.withValues(alpha: 0.55);

  /// A menu, which has to be solid to be read.
  Color get feedMenu =>
      _lightFeed ? Colors.white : _feedScheme.surfaceContainerHigh;

  BorderSide get feedRim =>
      _lightFeed ? BorderSide(color: noc.glassBorder) : BorderSide.none;
}
