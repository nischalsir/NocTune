import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/theme/cover_accent.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_theme.dart';
import '../../core/widgets/artwork.dart';
import '../../data/models/track.dart';
import '../../third_party/spotiflac/overflow_marquee.dart';
import '../library/track_menu.dart';
import '../lyrics/lyrics_offset.dart';
import '../lyrics/lyrics_source.dart';
import '../lyrics/lyrics_view.dart';
import '../settings/settings_controller.dart';
import 'audio_capabilities.dart';
import 'noc_audio_handler.dart';
import 'now_playing_route.dart';
import 'player_glass_button.dart';
import 'player_seek_bar.dart';
import 'queue_sheet.dart';

/// Opens the full player over the whole app.
Future<void> showNowPlaying(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(NowPlayingRoute(child: const NowPlayingScreen()));

/// The full-screen player. It is always dark: the cover, blurred and washed
/// with its own colours, is the backdrop, and everything on it is white.
///
/// From the top: a bar with the way out and the track's actions, the cover,
/// the title and artist beside the favourite and lyrics buttons, the seek
/// bar, previous / play / next, and a row with shuffle, the audio quality
/// and repeat. The lyrics button swaps the middle for the lyrics view, which
/// brings its own seek bar and transport.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _showLyrics = false;
  bool _lyricsFullscreen = false;

  // Marks the title row. The cover is drawn from the top of the screen down
  // to it, so its fade lands just above the title whatever the screen is.
  final _detailsKey = GlobalKey();
  double? _coverBottom;

  void _measureCover() {
    final details = _detailsKey.currentContext?.findRenderObject();
    final screen = context.findRenderObject();
    if (details is! RenderBox || !details.hasSize || screen == null) return;
    final top = details.localToGlobal(Offset.zero, ancestor: screen).dy;
    if (top > 0 && (top - (_coverBottom ?? -1)).abs() > 0.5) {
      setState(() => _coverBottom = top);
    }
  }

  void _setLyrics(bool show) => setState(() {
    _showLyrics = show;
    _lyricsFullscreen = false;
  });

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentMediaItemProvider).value;
    final settings = ref.watch(settingsProvider);
    final cover = settings.accentFromCover
        ? ref.watch(coverAccentProvider)
        : (light: null, dark: null);
    // The library's record of this track, ignored while it still belongs to
    // the previous one.
    final currentId = ref.watch(currentTrackIdProvider);
    final loaded = ref.watch(currentTrackProvider).value;
    final track = loaded != null && loaded.id == currentId ? loaded : null;
    final lyricsOpen = _showLyrics && item != null && track != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final screen = MediaQuery.sizeOf(context);
    // A phone on its side: no room for the cover above the controls.
    final sideways = screen.height < 560 && screen.width > screen.height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureCover();
    });

    return Theme(
      data: buildNocTheme(
        Brightness.dark,
        settings.accent,
        coverAccent: cover.dark,
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Always dark, so always light status bar icons.
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
        child: Material(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The backdrop cross-fades as the cover changes between tracks.
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 500),
                child: _Backdrop(
                  key: ValueKey(item?.artUri),
                  path: item?.artUri?.toFilePath(),
                ),
              ),
              if (item != null && !sideways)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _coverBottom ?? screen.height * 0.54,
                  child: _ArtworkHero(
                    path: item.artUri?.toFilePath(),
                    visible: !lyricsOpen,
                  ),
                ),
              // A veil that deepens the backdrop under the lyrics.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: lyricsOpen ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x9E000000),
                          Color(0x85000000),
                          Color(0x94000000),
                          Color(0xB8000000),
                        ],
                        stops: [0, 0.35, 0.70, 1],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (!(lyricsOpen && _lyricsFullscreen))
                      _TopBar(
                        item: item,
                        track: track,
                        lyricsOpen: lyricsOpen,
                        onLeaveLyrics: () => _setLyrics(false),
                      ),
                    Expanded(
                      child: item == null
                          ? const _NothingPlaying()
                          : AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 320),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.96,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: lyricsOpen
                                  ? Center(
                                      key: const ValueKey('lyrics'),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 720,
                                        ),
                                        child: LyricsPanel(
                                          track: track,
                                          duration:
                                              item.duration ?? track.duration,
                                          isFullscreen: _lyricsFullscreen,
                                          onToggleFullscreen: () => setState(
                                            () => _lyricsFullscreen =
                                                !_lyricsFullscreen,
                                          ),
                                        ),
                                      ),
                                    )
                                  : _NowPlaying(
                                      key: const ValueKey('player'),
                                      item: item,
                                      track: track,
                                      onShowLyrics: () => _setLyrics(true),
                                      detailsKey: _detailsKey,
                                      sideways: sideways,
                                    ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off_outlined,
              size: 42,
              color: Colors.white.withValues(alpha: 0.90),
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing is playing',
              textAlign: TextAlign.center,
              style: FlexType.headlineSmall.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a track from your library to start.',
              textAlign: TextAlign.center,
              style: FlexType.bodyMedium.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cover, blurred past recognition, under a dark wash, three soft pools
/// of the cover's colours, a top-to-bottom scrim that keeps text legible,
/// and a faint vignette.
///
/// None of it moves, so it is drawn once and kept as a picture. Otherwise
/// the blur and every wash would be worked out again on each frame that the
/// lyrics or the seek bar repaint, which is every frame while music plays.
class _Backdrop extends StatefulWidget {
  const _Backdrop({super.key, required this.path});

  final String? path;

  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> {
  final _picture = SnapshotController(allowSnapshotting: true);
  bool _coverDrawn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The pools take the theme's colours: draw again when those change.
    _picture.clear();
  }

  @override
  void dispose() {
    _picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = widget.path;

    Widget pool(Color color, Alignment center, double radius, List<double> a) =>
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: center,
              radius: radius,
              colors: [
                color.withValues(alpha: a[0]),
                color.withValues(alpha: a[1]),
                color.withValues(alpha: 0),
              ],
              stops: [0, a[2], 1],
            ),
          ),
        );

    return SnapshotWidget(
      controller: _picture,
      // Drawn again at the new size when the window changes.
      autoresize: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path != null)
            Opacity(
              opacity: 0.9,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: Image.file(
                  File(path),
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
            ),
          const ColoredBox(color: Color(0x85000000)),
          pool(scheme.primary, const Alignment(-0.5, -0.6), 0.85, [
            0.58,
            0.22,
            0.45,
          ]),
          pool(scheme.secondary, const Alignment(0.76, 0.3), 0.78, [
            0.52,
            0.20,
            0.50,
          ]),
          pool(
            Color.lerp(scheme.tertiary, Colors.black, 0.35)!,
            const Alignment(-0.7, 0.64),
            0.70,
            [0.42, 0.14, 0.55],
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x59000000),
                  Color(0x26000000),
                  Color(0x66000000),
                  Color(0xB8000000),
                ],
                stops: [0, 0.28, 0.65, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 0.8,
                colors: [
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x4D000000),
                ],
                stops: [0, 0.65, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LyricsAction { import, remove }

/// The way out on the left, what is showing in the middle, and the actions
/// for it on the right: the queue and the track's menu on the player; the
/// sync offset and the lyrics menu on the lyrics view.
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.item,
    required this.track,
    required this.lyricsOpen,
    required this.onLeaveLyrics,
  });

  final MediaItem? item;
  final Track? track;
  final bool lyricsOpen;
  final VoidCallback onLeaveLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = this.track;
    final scheme = Theme.of(context).colorScheme;
    final subtitle = item?.album;

    final actions = <Widget>[];
    if (track != null && lyricsOpen) {
      final found = ref
          .watch(lyricsProvider((trackId: track.id, uri: track.uri)))
          .value;
      if (found != null && found.lyrics.synced) {
        final offset = ref.watch(lyricsOffsetOfProvider(track.id));
        actions.add(
          PlayerGlassButton(
            icon: Icons.timer,
            fill: 0.16,
            iconSize: 22,
            label: 'Lyrics sync offset',
            color: offset == 0 ? null : scheme.primary.withValues(alpha: 0.35),
            foreground: offset == 0 ? null : scheme.primary,
            onTap: () => showLyricsOffsetDialog(context, track.id),
          ),
        );
      }
      actions.add(
        PopupMenuButton<_LyricsAction>(
          tooltip: 'Lyrics options',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onSelected: (action) => switch (action) {
            _LyricsAction.import => importLyricsWithFeedback(
              context,
              ref,
              track,
            ),
            _LyricsAction.remove => removeImportedLyrics(ref, track),
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _LyricsAction.import,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.file_open_outlined),
                title: Text('Import lyrics file…'),
              ),
            ),
            if (found?.origin == LyricsOrigin.imported)
              const PopupMenuItem(
                value: _LyricsAction.remove,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Remove imported lyrics'),
                ),
              ),
          ],
          // The menu button owns the tap, the tooltip and the semantics;
          // the circle only draws.
          child: const IgnorePointer(
            child: ExcludeSemantics(child: _MenuCircle()),
          ),
        ),
      );
    } else if (track != null) {
      actions
        ..add(
          PlayerGlassButton(
            icon: Icons.queue_music,
            frosted: true,
            fill: 0.16,
            iconSize: 22,
            label: 'Queue',
            onTap: () => showQueueSheet(context),
          ),
        )
        ..add(
          PlayerGlassButton(
            icon: Icons.more_vert,
            frosted: true,
            fill: 0.16,
            iconSize: 22,
            label: 'More for this track',
            onTap: () => showTrackMenu(context, ref, track),
          ),
        );
    }

    // The frosted buttons share one reading of what is behind them.
    return BackdropGroup(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    // Over the lyrics there is only the blurred backdrop behind
                    // the buttons, so blurring it again would show nothing.
                    child: lyricsOpen
                        ? PlayerGlassButton(
                            icon: Icons.arrow_back,
                            fill: 0.16,
                            iconSize: 26,
                            label: 'Back to the player',
                            onTap: onLeaveLyrics,
                          )
                        : PlayerGlassButton(
                            icon: Icons.expand_more,
                            frosted: true,
                            fill: 0.16,
                            iconSize: 26,
                            label: 'Close player',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                  ),
                  Padding(
                    // Clear of the buttons on either side.
                    padding: const EdgeInsets.symmetric(horizontal: 104),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lyricsOpen ? 'LYRICS' : 'NOW PLAYING',
                          maxLines: 1,
                          style:
                              FlexType.custom(
                                size: 12,
                                lineHeight: 16,
                                weight: 540,
                                letterSpacing: 0.4,
                              ).copyWith(
                                color: Colors.white.withValues(alpha: 0.95),
                              ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                FlexType.custom(
                                  size: 13,
                                  lineHeight: 18,
                                  weight: 420,
                                ).copyWith(
                                  color: Colors.white.withValues(alpha: 0.70),
                                ),
                          ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, action) in actions.indexed) ...[
                          if (index > 0) const SizedBox(width: 8),
                          action,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuCircle extends StatelessWidget {
  const _MenuCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.fromBorderSide(kPlayerGlassRim),
      ),
      child: Icon(
        Icons.more_vert,
        size: 22,
        color: Colors.white.withValues(alpha: 0.94),
      ),
    );
  }
}

/// The player's controls: details, seek bar, transport and the mode row.
///
/// Upright, they rest at the bottom of the screen; the cover is not a card
/// among them but the top of the backdrop, drawn edge to edge by
/// [_ArtworkHero] down to where the title starts. On its side (a phone in
/// landscape) there is no room for that, so the cover sits beside them.
class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({
    super.key,
    required this.item,
    required this.track,
    required this.onShowLyrics,
    required this.detailsKey,
    required this.sideways,
  });

  final MediaItem item;
  final Track? track;
  final VoidCallback onShowLyrics;

  /// Marks the title row, so the screen knows where the cover must end.
  final GlobalKey detailsKey;
  final bool sideways;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = item.duration ?? Duration.zero;
    final wave = ref.watch(settingsProvider.select((s) => s.waveSeekBar));
    final details = KeyedSubtree(
      key: detailsKey,
      child: _Details(item: item, track: track, onShowLyrics: onShowLyrics),
    );
    final seekBar = PlayerSeekBar(duration: duration, wave: wave);
    final modes = _ModeRow(track: track);

    return LayoutBuilder(
      builder: (context, box) {
        if (sideways) {
          final side = math.min(box.maxHeight - 16, 370.0);
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                _Cover(path: item.artUri?.toFilePath(), size: side - 28),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        details,
                        const SizedBox(height: 8),
                        seekBar,
                        const SizedBox(height: 8),
                        const _Transport(),
                        const SizedBox(height: 12),
                        modes,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // If the text is too large for everything to fit, this scrolls
        // rather than overflowing; it starts at the bottom, on the controls.
        return SingleChildScrollView(
          reverse: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      details,
                      const SizedBox(height: 14),
                      seekBar,
                      const SizedBox(height: 14),
                      const _Transport(),
                      const SizedBox(height: 24),
                      modes,
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

/// The cover as the top of the player: the full width of the screen from
/// its very top, cropped from the top of the picture, and dissolving over
/// its last two fifths into the blurred backdrop behind the controls. It
/// cross-fades when the track changes and steps aside for the lyrics.
///
/// A track without a cover gets a quiet glass disc with a note in its place.
class _ArtworkHero extends StatelessWidget {
  const _ArtworkHero({required this.path, required this.visible});

  final String? path;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.fastOutSlowIn,
        child: path == null
            ? Center(
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Icon(
                    Icons.music_note,
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
              )
            : ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.58, 1],
                ).createShader(bounds),
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 350),
                  child: Image.file(
                    File(path),
                    key: ValueKey(path),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    // Decoded at the width it is shown, not the file's own.
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The cover as a rounded card, for the sideways layout.
class _Cover extends StatelessWidget {
  const _Cover({required this.path, required this.size});

  final String? path;
  final double size;

  static const _radius = 22.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Artwork(path: path, size: size, radius: _radius),
    );
  }
}

/// Title over the artist, with favourite and lyrics beside them.
class _Details extends ConsumerWidget {
  const _Details({
    required this.item,
    required this.track,
    required this.onShowLyrics,
  });

  final MediaItem item;
  final Track? track;
  final VoidCallback onShowLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = this.track;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
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
                  // A title too long for the line scrolls past.
                  OverflowMarquee(
                    resetKey: (item.id, item.title),
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlexType.custom(
                        size: 24,
                        lineHeight: 32,
                        weight: 540,
                        letterSpacing: -0.2,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.artist ?? 'Unknown artist',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FlexType.custom(
                      size: 17,
                      lineHeight: 24,
                      weight: 420,
                    ).copyWith(color: Colors.white.withValues(alpha: 0.72)),
                  ),
                ],
              ),
            ),
          ),
          if (track != null) ...[
            const SizedBox(width: 12),
            PlayerGlassButton(
              icon: track.isFavorite ? Icons.favorite : Icons.favorite_border,
              label: track.isFavorite
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              size: 46,
              color: track.isFavorite
                  ? Colors.white.withValues(alpha: 0.92)
                  : null,
              foreground: track.isFavorite
                  ? scheme.primary
                  : Colors.white.withValues(alpha: 0.85),
              onTap: () => ref
                  .read(libraryRepositoryProvider)
                  .setFavorite(track.id, favorite: !track.isFavorite),
            ),
            const SizedBox(width: 8),
            PlayerGlassButton(
              icon: Icons.format_quote,
              label: 'Show lyrics',
              size: 46,
              foreground: Colors.white.withValues(alpha: 0.90),
              onTap: onShowLyrics,
            ),
          ],
        ],
      ),
    );
  }
}

/// Previous, the wide play/pause pill, and next.
class _Transport extends ConsumerWidget {
  const _Transport();

  static const _side = 54.0;
  static const _gap = 18.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final busy = ref.watch(
      playbackStateProvider.select((state) {
        final processing = state.value?.processingState;
        return processing == AudioProcessingState.loading ||
            processing == AudioProcessingState.buffering;
      }),
    );
    NocAudioHandler handler() => ref.read(audioHandlerProvider);

    return LayoutBuilder(
      builder: (context, box) {
        final pill = (box.maxWidth - _side * 2 - _gap * 2).clamp(112.0, 180.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayerGlassButton(
              icon: Icons.skip_previous,
              label: 'Previous',
              size: _side,
              iconSize: 28,
              onTap: () => handler().skipToPrevious(),
            ),
            const SizedBox(width: _gap),
            _PlayPill(
              width: pill,
              playing: playing,
              busy: busy,
              onTap: () => playing ? handler().pause() : handler().play(),
            ),
            const SizedBox(width: _gap),
            PlayerGlassButton(
              icon: Icons.skip_next,
              label: 'Next',
              size: _side,
              iconSize: 28,
              onTap: () => handler().skipToNext(),
            ),
          ],
        );
      },
    );
  }
}

class _PlayPill extends StatefulWidget {
  const _PlayPill({
    required this.width,
    required this.playing,
    required this.busy,
    required this.onTap,
  });

  final double width;
  final bool playing;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_PlayPill> createState() => _PlayPillState();
}

class _PlayPillState extends State<_PlayPill> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.playing ? 'Pause' : 'Play';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed && !reduceMotion ? 0.92 : 1,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: Material(
              color: kPlayerGlassFill,
              shape: const StadiumBorder(side: kPlayerGlassRim),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                child: SizedBox(
                  width: widget.width,
                  height: 56,
                  child: Center(
                    child: widget.busy
                        ? const SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: FlexType.custom(
                                      size: 16,
                                      lineHeight: 24,
                                      weight: 540,
                                    ).copyWith(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shuffle, what the audio is, and repeat.
class _ModeRow extends ConsumerWidget {
  const _ModeRow({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffling = ref.watch(
      playbackStateProvider.select(
        (state) =>
            (state.value?.shuffleMode ?? AudioServiceShuffleMode.none) !=
            AudioServiceShuffleMode.none,
      ),
    );
    final repeat = ref.watch(
      playbackStateProvider.select(
        (state) => state.value?.repeatMode ?? AudioServiceRepeatMode.none,
      ),
    );
    NocAudioHandler handler() => ref.read(audioHandlerProvider);

    return Row(
      children: [
        Expanded(
          flex: 10,
          child: _ModeButton(
            icon: Icons.shuffle,
            label: shuffling ? 'Shuffle on' : 'Shuffle off',
            active: shuffling,
            onTap: () => handler().setShuffleMode(
              shuffling
                  ? AudioServiceShuffleMode.none
                  : AudioServiceShuffleMode.all,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(flex: 18, child: _QualityPill(track: track)),
        const SizedBox(width: 10),
        Expanded(
          flex: 10,
          child: _ModeButton(
            icon: repeat == AudioServiceRepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            label: switch (repeat) {
              AudioServiceRepeatMode.one => 'Repeat one',
              AudioServiceRepeatMode.none => 'Repeat off',
              _ => 'Repeat all',
            },
            active: repeat != AudioServiceRepeatMode.none,
            // Off, then the whole queue, then this track.
            onTap: () => handler().setRepeatMode(switch (repeat) {
              AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
              AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
              _ => AudioServiceRepeatMode.one,
            }),
          ),
        ),
      ],
    );
  }
}

/// A wide glass button for a mode that is on or off. On, it takes the
/// accent and shows a dot under its icon.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active
        ? scheme.onPrimaryContainer
        : Colors.white.withValues(alpha: 0.85);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        toggled: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: active
              ? scheme.primaryContainer.withValues(alpha: 0.86)
              : kPlayerGlassFill,
          shape: StadiumBorder(
            side: active ? BorderSide.none : kPlayerGlassRim,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 19, color: foreground),
                  if (active)
                    Positioned(
                      bottom: 5,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: foreground,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the audio of this track is, in the middle of the mode row. Tapping
/// it shows the track's details.
///
/// "Lossless" is only claimed for files confirmed lossless by their
/// contents, and "Dolby Atmos" only for Atmos recordings on a device that
/// reports a decoder for them. Nothing is shown for a track whose record
/// hasn't loaded, so one track's format is never shown for another.
class _QualityPill extends ConsumerWidget {
  const _QualityPill({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = this.track;
    final badges = formatBadges(
      track?.codec,
      deviceDecodesAtmos: ref.watch(deviceDecodesAtmosProvider).value ?? false,
    );
    final label = track == null
        ? ''
        : qualityBadgeLabel(track, atmos: badges.atmos);
    final description = badges.atmos
        ? 'Dolby Atmos'
        : (badges.lossless ? 'Lossless quality' : 'Audio quality');
    final color = Colors.white.withValues(alpha: 0.95);

    return Semantics(
      button: track != null,
      label: track == null ? null : '$description: $label',
      excludeSemantics: true,
      child: Material(
        color: kPlayerGlassFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: kPlayerGlassRim,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: track == null ? null : () => showTrackDetails(context, track),
          child: SizedBox(
            height: 44,
            child: track == null
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    // Shrinks rather than cutting a long description short.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            badges.atmos
                                ? Icons.surround_sound
                                : (badges.lossless
                                      ? Icons.high_quality
                                      : Icons.music_note),
                            size: badges.atmos ? 19 : 17,
                            color: color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            maxLines: 1,
                            style: FlexType.custom(
                              size: 11.5,
                              lineHeight: 16,
                              weight: 540,
                            ).copyWith(letterSpacing: 0.4, color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
