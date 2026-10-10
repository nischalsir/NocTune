import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/flex_type.dart';
import '../../data/models/track.dart';
import '../playback/noc_audio_handler.dart';
import '../playback/player_glass_button.dart';
import '../playback/player_seek_bar.dart';
import '../settings/settings_controller.dart';
import 'lyrics.dart';
import 'lyrics_offset.dart';
import 'lyrics_source.dart';

/// Lets the user pick a lyrics file for [track], and says so when the file
/// holds nothing readable.
Future<void> importLyricsWithFeedback(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await importLyricsFor(track, ref);
  } on InvalidLyricsFile {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'That file has no lyrics NocTune can read. Try another file.',
          ),
        ),
      );
  }
}

/// Forgets the lyrics file imported for [track]; lyrics beside or inside the
/// audio file, if any, show again.
Future<void> removeImportedLyrics(WidgetRef ref, Track track) async {
  await ref.read(libraryRepositoryProvider).removeImportedLyrics(track.id);
  ref.invalidate(lyricsProvider((trackId: track.id, uri: track.uri)));
}

/// The lyrics view of the player, for a dark backdrop: the lyrics fill the
/// space, and beneath them sit the text-size and fullscreen buttons, a seek
/// bar and the transport buttons.
///
/// Synced lyrics follow the real playback position: the line being sung is
/// large, bright and sharp, its neighbours recede, and the list keeps it a
/// third of the way down. Tapping a line seeks to it. Lyrics without
/// timestamps are shown as plain text and are labelled as not synced; no
/// timing is ever invented for them.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.track,
    required this.duration,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });

  final Track track;

  /// Length of the track as the player reports it.
  final Duration duration;

  /// Whether the lyrics have the whole screen: the seek bar and transport
  /// are hidden then.
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  bool _showSizeSlider = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final loaded = ref.watch(
      lyricsProvider((trackId: track.id, uri: track.uri)),
    );
    final scale = ref.watch(settingsProvider.select((s) => s.lyricsScale));
    final wave = ref.watch(settingsProvider.select((s) => s.waveSeekBar));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final found = loaded.value;

    final Widget content;
    if (loaded.isLoading && found == null) {
      content = const _Loading(key: ValueKey('loading'));
    } else if (found == null) {
      content = _Empty(
        key: const ValueKey('empty'),
        failed: loaded.hasError,
        onImport: () => importLyricsWithFeedback(context, ref, track),
      );
    } else if (found.lyrics.synced) {
      content = _SyncedLyrics(
        // A new track starts at the top with fresh state.
        key: ValueKey('synced-${track.id}'),
        trackId: track.id,
        lyrics: found.lyrics,
        origin: found.origin,
        scale: scale,
      );
    } else {
      content = _PlainLyrics(
        key: ValueKey('plain-${track.id}'),
        lyrics: found.lyrics,
        scale: scale,
      );
    }

    // A window too short for everything keeps the lyrics and drops the seek
    // bar and transport, as fullscreen does.
    return LayoutBuilder(
      builder: (context, box) {
        final lyricsOnly = widget.isFullscreen || box.maxHeight < 420;
        return Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.96,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: content,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    alignment: Alignment.bottomCenter,
                    child: _showSizeSlider
                        ? _SizeSlider(scale: scale)
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PlayerGlassButton(
                        icon: Icons.format_size,
                        label: 'Adjust lyrics text size',
                        iconSize: 22,
                        pressedScale: 0.82,
                        color: _showSizeSlider || scale != 1
                            ? Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.28)
                            : null,
                        foreground: _showSizeSlider || scale != 1
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white.withValues(alpha: 0.90),
                        onTap: () =>
                            setState(() => _showSizeSlider = !_showSizeSlider),
                      ),
                      const SizedBox(width: 10),
                      PlayerGlassButton(
                        icon: widget.isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        label: widget.isFullscreen
                            ? 'Exit fullscreen lyrics'
                            : 'Fullscreen lyrics',
                        pressedScale: 0.82,
                        foreground: Colors.white.withValues(alpha: 0.90),
                        onTap: widget.onToggleFullscreen,
                      ),
                    ],
                  ),
                  if (!lyricsOnly) ...[
                    const SizedBox(height: 6),
                    PlayerSeekBar(
                      duration: widget.duration,
                      wave: wave,
                      showTimes: false,
                    ),
                    const SizedBox(height: 6),
                    _Transport(duration: widget.duration),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- Content states ----

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Finding lyrics…',
            style: FlexType.bodyLarge.copyWith(
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.failed, required this.onImport});

  /// Whether lyrics exist but could not be read.
  final bool failed;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics,
              size: 42,
              color: Colors.white.withValues(alpha: 0.90),
            ),
            const SizedBox(height: 14),
            Text(
              failed ? "Couldn't read the lyrics" : 'No lyrics',
              textAlign: TextAlign.center,
              style: FlexType.headlineSmall.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              failed
                  ? 'The lyrics stored with this track could not be opened.'
                  : 'No lyrics were found in this track or beside it. You '
                        'can add them from an .lrc or text file.',
              textAlign: TextAlign.center,
              style: FlexType.bodyMedium.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined, size: 18),
              label: const Text('Import lyrics file'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({super.key, required this.lyrics, required this.scale});

  final Lyrics lyrics;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_disabled,
                size: 16,
                color: Colors.white.withValues(alpha: 0.90),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Lyrics not time-synced',
                  style: FlexType.labelSmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // The size slider is the control for this text; the system text
          // size adds to it only up to a point, so words still fit a line.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: _maxSystemTextScale,
            child: Text(
              lyrics.lines.map((line) => line.text).join('\n'),
              style: FlexType.custom(
                size: 28 * scale,
                lineHeight: 46 * scale,
                weight: 500,
                width: 102,
                round: 18,
                letterSpacing: 0.1,
              ).copyWith(color: Colors.white.withValues(alpha: 0.94)),
            ),
          ),
        ],
      ),
    );
  }
}

/// How far the system text size may enlarge lyrics on top of the app's own
/// size slider.
const _maxSystemTextScale = 1.3;

/// How much the line being sung is enlarged.
const _activeScale = 1.085;

/// Timestamped lyrics that follow playback.
class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({
    super.key,
    required this.trackId,
    required this.lyrics,
    required this.origin,
    required this.scale,
  });

  final int trackId;
  final Lyrics lyrics;
  final LyricsOrigin origin;
  final double scale;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  // How long the list leaves the user alone after they scroll it.
  static const _handsOff = Duration(milliseconds: 2200);

  late List<GlobalKey> _keys = _makeKeys();
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dragging = false;

  List<GlobalKey> _makeKeys() => [
    for (var i = 0; i < widget.lyrics.lines.length; i++) GlobalKey(),
  ];

  @override
  void initState() {
    super.initState();
    // Opens on the line being sung rather than at the top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _follow(
        _indexAt(
          ref.read(lyricsPositionProvider),
          ref.read(lyricsOffsetOfProvider(widget.trackId)),
        ),
        animate: false,
      );
    });
  }

  @override
  void didUpdateWidget(_SyncedLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics.lines.length != widget.lyrics.lines.length) {
      _keys = _makeKeys();
    }
  }

  /// The line being sung at [position], shifted by the track's saved
  /// timing correction.
  int _indexAt(AsyncValue<Duration> position, int offsetMs) =>
      widget.lyrics.indexAt(
        (position.value ?? Duration.zero) + Duration(milliseconds: offsetMs),
      );

  /// Scrolls the active line to a third of the way down, unless the user
  /// has just been scrolling.
  void _follow(int index, {bool animate = true}) {
    if (index < 0 || index >= _keys.length) return;
    if (DateTime.now().difference(_userScrolledAt) < _handsOff) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[index].currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1 / 3,
        duration: !animate || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _onScroll(ScrollNotification notification) {
    final byHand = switch (notification) {
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (byHand) {
      _userScrolledAt = DateTime.now();
      if (!_dragging) setState(() => _dragging = true);
    } else if (notification is ScrollEndNotification && _dragging) {
      setState(() => _dragging = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final offset = ref.watch(lyricsOffsetOfProvider(widget.trackId));
    // The position ticks twenty times a second, but this only rebuilds when
    // the line changes.
    final active = ref.watch(
      lyricsPositionProvider.select((p) => _indexAt(p, offset)),
    );
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    ref.listen(
      lyricsPositionProvider.select((p) => _indexAt(p, offset)),
      (_, index) => _follow(index),
    );

    final style = FlexType.custom(
      size: 30 * widget.scale,
      lineHeight: 30 * widget.scale * 1.38,
      weight: 700,
      width: 102,
      round: 18,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'LINE SYNC • ${widget.origin.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlexType.labelSmall.copyWith(
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // The widest a line may be laid out so that, enlarged as the
                // active line, it still ends inside the screen's edge. Line
                // breaks never change when a line becomes active.
                final textWidth = math.max(
                  80.0,
                  (box.maxWidth - 16) / _activeScale - 12,
                );
                return MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _maxSystemTextScale,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 40, 16, 130),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, line) in lines.indexed)
                            Padding(
                              key: _keys[index],
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : 26,
                              ),
                              child: _LyricRow(
                                text: line.text,
                                style: style,
                                textWidth: textWidth,
                                relative: active < 0 ? null : index - active,
                                playing: playing,
                                browsing: _dragging,
                                onTap: line.time == null
                                    ? null
                                    : () => ref
                                          .read(audioHandlerProvider)
                                          .seek(line.time!),
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
      ),
    );
  }
}

/// One lyric line. How it looks depends on where it is relative to the line
/// being sung: that one is enlarged, bright and sharp with a soft glow; the
/// further away a line is, the dimmer and softer it gets.
///
/// Its size on the page never changes, so the lines around it don't move
/// when it becomes active: the enlargement, the lift and the blur are all
/// painted effects.
class _LyricRow extends StatefulWidget {
  const _LyricRow({
    required this.text,
    required this.style,
    required this.textWidth,
    required this.relative,
    required this.playing,
    required this.browsing,
    required this.onTap,
  });

  final String text;
  final TextStyle style;
  final double textWidth;

  /// Lines from the active one: negative above, positive below, zero for
  /// the active line itself. Null before the first line is reached.
  final int? relative;
  final bool playing;

  /// Whether the user is scrolling the list, which brings every line back
  /// into focus.
  final bool browsing;
  final VoidCallback? onTap;

  @override
  State<_LyricRow> createState() => _LyricRowState();
}

class _LyricRowState extends State<_LyricRow> with TickerProviderStateMixin {
  // Lines further than this from the active one are off screen while the
  // list is following, so they are not given a blur layer.
  static const _blurReach = 8;

  // Made only for lines that actually animate.
  AnimationController? _onset;
  AnimationController? _trail;
  double _trailFrom = 0;
  Curve _trailCurve = Curves.linear;

  @override
  void didUpdateWidget(_LyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final relative = widget.relative;
    if (relative == oldWidget.relative) return;
    final animate = widget.playing && !MediaQuery.disableAnimationsOf(context);

    // The pulse a line gives as it becomes the active one.
    if (relative == 0 && animate) {
      (_onset ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 480),
      )).forward(from: 0);
    } else {
      _onset?.value = 0;
    }

    // Lines at and below the new active one lag, then spring up in turn.
    if (animate &&
        !widget.browsing &&
        relative != null &&
        relative >= 0 &&
        relative <= 6 &&
        oldWidget.relative != null) {
      _trailFrom = 10.0 + relative * 4;
      const settle = 620;
      final wait = relative * 38;
      _trailCurve = Interval(
        wait / (wait + settle),
        1,
        curve: const _Spring(ratio: 0.72, stiffness: 180, seconds: 0.62),
      );
      (_trail ??= AnimationController(vsync: this))
        ..duration = Duration(milliseconds: wait + settle)
        ..forward(from: 0);
    } else {
      _trail?.value = 1;
    }
  }

  @override
  void dispose() {
    _onset?.dispose();
    _trail?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relative = widget.relative;
    final isActive = relative == 0;
    final distance = relative?.abs() ?? 99;
    final isPast = relative != null && relative < 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Duration timed(int ms) =>
        reduceMotion ? Duration.zero : Duration(milliseconds: ms);
    final start = AlignmentDirectional.centerStart.resolve(
      Directionality.of(context),
    );

    final scale = isActive ? _activeScale : (distance == 1 ? 0.99 : 0.965);
    // Dimming is done in the text colour, not with a layer per line.
    final opacity = isActive
        ? 1.0
        : 0.44 * (distance == 1 ? 0.58 : (isPast ? 0.38 : 0.30));
    final blur =
        isActive || widget.browsing || relative == null || distance > _blurReach
        ? 0.0
        : math.min(distance, 4) * 1.6;
    final shift = isActive ? -3.5 : (isPast ? -1.5 : 3.5);
    final onset = _onset;
    final trail = _trail;

    final text = AnimatedDefaultTextStyle(
      duration: timed(320),
      curve: Curves.fastOutSlowIn,
      style: widget.style.copyWith(
        color: Colors.white.withValues(alpha: opacity),
        shadows: [
          Shadow(
            color: Colors.white.withValues(alpha: isActive ? 0.50 : 0),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(widget.text.trim().isEmpty ? '♪' : widget.text),
    );

    final row = TweenAnimationBuilder<double>(
      tween: Tween(end: blur),
      duration: timed(380),
      curve: Curves.fastOutSlowIn,
      builder: (context, radius, child) => ImageFiltered(
        enabled: radius > 0.2,
        // A blur radius, expressed as the sigma the filter wants.
        imageFilter: ImageFilter.blur(
          sigmaX: radius * 0.58,
          sigmaY: radius * 0.58,
          tileMode: TileMode.decal,
        ),
        child: child,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: shift),
        duration: timed(520),
        curve: const _Spring(ratio: 0.82, stiffness: 400, seconds: 0.52),
        builder: (context, dy, child) => AnimatedBuilder(
          animation: Listenable.merge([?onset, ?trail]),
          builder: (context, child) {
            final lag = trail == null
                ? 0.0
                : _trailFrom * (1 - _trailCurve.transform(trail.value));
            final wave = onset != null && onset.isAnimating
                ? math.sin(
                    math.pi * Curves.fastOutSlowIn.transform(onset.value),
                  )
                : 0.0;
            return Transform.translate(
              offset: Offset(0, dy + lag),
              child: Transform.scale(
                scale: 1 + 0.020 * wave,
                alignment: start,
                child: child,
              ),
            );
          },
          child: child,
        ),
        child: AnimatedScale(
          scale: scale,
          alignment: start,
          duration: timed(600),
          curve: const _Spring(ratio: 0.62, stiffness: 260, seconds: 0.6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.textWidth),
                child: text,
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: widget.onTap != null,
      selected: isActive,
      hint: widget.onTap == null ? null : 'Plays from this line',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

/// The response of a spring released away from rest, as an animation curve:
/// it can run past the target and settle back.
class _Spring extends Curve {
  const _Spring({
    required this.ratio,
    required this.stiffness,
    required this.seconds,
  });

  /// Damping ratio: below 1 it overshoots.
  final double ratio;
  final double stiffness;

  /// How long the curve is given to settle.
  final double seconds;

  @override
  double transformInternal(double t) {
    final time = t * seconds;
    final natural = math.sqrt(stiffness);
    if (ratio >= 1) {
      return 1 - math.exp(-natural * time) * (1 + natural * time);
    }
    final damped = natural * math.sqrt(1 - ratio * ratio);
    return 1 -
        math.exp(-ratio * natural * time) *
            (math.cos(damped * time) +
                ratio * natural / damped * math.sin(damped * time));
  }
}

// ---- Controls ----

/// Text size for the lyrics, with a way back to the default.
class _SizeSlider extends ConsumerWidget {
  const _SizeSlider({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lyrics size: ${(scale * 100).round()}%',
                    style: FlexType.labelMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.90),
                    ),
                  ),
                ),
                if (scale != 1)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => settings.setLyricsScale(1),
                    child: Text('Reset', style: FlexType.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                ExcludeSemantics(
                  child: Text(
                    'A',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.70),
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: scale,
                    min: SettingsController.minLyricsScale,
                    max: SettingsController.maxLyricsScale,
                    semanticFormatterCallback: (value) =>
                        'Lyrics size ${(value * 100).round()} percent',
                    onChanged: settings.setLyricsScale,
                  ),
                ),
                ExcludeSemantics(
                  child: Text(
                    'A',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Elapsed time, previous / play-pause / next, and time remaining.
class _Transport extends ConsumerWidget {
  const _Transport({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      playbackPositionProvider.select(
        (p) => Duration(seconds: p.value?.inSeconds ?? 0),
      ),
    );
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
    final shown = position > duration && duration > Duration.zero
        ? duration
        : position;
    final remaining = duration - shown;
    final timeStyle = FlexType.labelSmall.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    NocAudioHandler handler() => ref.read(audioHandlerProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(formatDuration(shown), maxLines: 1, style: timeStyle),
          ),
          PlayerGlassButton(
            icon: Icons.skip_previous,
            label: 'Previous',
            size: 46,
            onTap: () => handler().skipToPrevious(),
          ),
          const SizedBox(width: 16),
          if (busy)
            const SizedBox.square(
              dimension: 56,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            PlayerGlassButton(
              icon: playing ? Icons.pause : Icons.play_arrow,
              label: playing ? 'Pause' : 'Play',
              size: 56,
              iconSize: 28,
              fill: 0.18,
              onTap: () => playing ? handler().pause() : handler().play(),
            ),
          const SizedBox(width: 16),
          PlayerGlassButton(
            icon: Icons.skip_next,
            label: 'Next',
            size: 46,
            onTap: () => handler().skipToNext(),
          ),
          Expanded(
            child: Text(
              '−${formatDuration(remaining < Duration.zero ? Duration.zero : remaining)}',
              maxLines: 1,
              textAlign: TextAlign.end,
              style: timeStyle,
            ),
          ),
        ],
      ),
    );
  }
}
