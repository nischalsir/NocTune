import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'lyric_fill.dart';
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

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics>
    with SingleTickerProviderStateMixin {
  // How long the list leaves the user alone after they scroll it.
  static const _handsOff = Duration(milliseconds: 2200);
  // The furthest the clock runs ahead of the last position it was told.
  static const _maxCoast = Duration(milliseconds: 300);

  late List<GlobalKey> _keys = _makeKeys();
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _dragging = false;

  // The playback position for the word fill, on every frame. The player
  // reports it twenty times a second; between reports this runs on from the
  // last one, so the fill moves at the screen's own refresh rate.
  final _clock = ValueNotifier(Duration.zero);
  late final _frames = createTicker((_) => _tick());
  final _sinceReport = Stopwatch();
  Duration _reported = Duration.zero;
  int _offsetMs = 0;
  bool _playing = false;

  List<GlobalKey> _makeKeys() => [
    for (var i = 0; i < widget.lyrics.lines.length; i++) GlobalKey(),
  ];

  void _tick() {
    final coast = _playing ? _sinceReport.elapsed : Duration.zero;
    _clock.value =
        _reported +
        (coast > _maxCoast ? _maxCoast : coast) +
        Duration(milliseconds: _offsetMs);
  }

  @override
  void initState() {
    super.initState();
    _reported = ref.read(lyricsPositionProvider).value ?? Duration.zero;
    _sinceReport.start();
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

  @override
  void dispose() {
    _frames.dispose();
    _clock.dispose();
    super.dispose();
  }

  /// The line being sung at [position], shifted by the track's saved
  /// timing correction.
  int _indexAt(AsyncValue<Duration> position, int offsetMs) =>
      widget.lyrics.indexAt(
        (position.value ?? Duration.zero) + Duration(milliseconds: offsetMs),
      );

  /// Glides the active line to a third of the way down, unless the user has
  /// just been scrolling.
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
            : const Duration(milliseconds: 760),
        // Leaves quickly and takes its time arriving, with no bounce.
        curve: const Cubic(0.22, 1, 0.36, 1),
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
    ref
      ..listen(
        lyricsPositionProvider.select((p) => _indexAt(p, offset)),
        (_, index) => _follow(index),
      )
      ..listen(lyricsPositionProvider, (_, position) {
        _reported = position.value ?? _reported;
        _sinceReport
          ..reset()
          ..start();
        _tick();
      });

    // With reduced motion the line lights up at once instead of filling.
    final sweep = !MediaQuery.disableAnimationsOf(context);
    _offsetMs = offset;
    _playing = playing;
    if (sweep && playing) {
      if (!_frames.isActive) _frames.start();
    } else if (_frames.isActive) {
      _frames.stop();
    }
    _tick();

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
                // Says which kind of timing the file really has.
                '${widget.lyrics.wordSynced ? 'WORD SYNC' : 'LINE SYNC'} '
                '• ${widget.origin.label}',
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
                                // The line being sung fills as it goes; the
                                // one just sung keeps its fill while it
                                // fades back.
                                fill:
                                    sweep &&
                                        active >= 0 &&
                                        (index == active || index == active - 1)
                                    ? (
                                        units: lyricUnits(
                                          line,
                                          nextLineAt: index + 1 < lines.length
                                              ? lines[index + 1].time
                                              : null,
                                        ),
                                        position: _clock,
                                      )
                                    : null,
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

/// What a row needs to fill word by word.
typedef _Fill = ({List<LyricUnit> units, ValueListenable<Duration> position});

/// One lyric line. How it looks depends on where it is relative to the line
/// being sung: that one is enlarged and sharp and lights up word by word;
/// the further away a line is, the dimmer and softer it gets.
///
/// Its size on the page never changes, so the lines around it don't move
/// when it becomes active: the enlargement, the lift and the blur are all
/// painted effects, and they ease in and out rather than snapping.
class _LyricRow extends StatefulWidget {
  const _LyricRow({
    required this.text,
    required this.style,
    required this.textWidth,
    required this.relative,
    required this.playing,
    required this.browsing,
    required this.fill,
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

  /// Set for the active line and the one before it; null lights the active
  /// line all at once.
  final _Fill? fill;
  final VoidCallback? onTap;

  @override
  State<_LyricRow> createState() => _LyricRowState();
}

class _LyricRowState extends State<_LyricRow> with TickerProviderStateMixin {
  // Lines further than this from the active one are off screen while the
  // list is following, so they are not given a blur layer.
  static const _blurReach = 8;
  // An unhurried ease with no overshoot, shared by the row's changes.
  static const _ease = Cubic(0.22, 1, 0.36, 1);

  // Made only for lines that actually animate.
  AnimationController? _trail;
  double _trailFrom = 0;
  Curve _trailCurve = Curves.linear;

  @override
  void didUpdateWidget(_LyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final relative = widget.relative;
    if (relative == oldWidget.relative) return;
    final animate = widget.playing && !MediaQuery.disableAnimationsOf(context);

    // Lines at and below the new active one lag, then settle in turn.
    if (animate &&
        !widget.browsing &&
        relative != null &&
        relative >= 0 &&
        relative <= 6 &&
        oldWidget.relative != null) {
      _trailFrom = 8.0 + relative * 3;
      const settle = 820;
      final wait = relative * 45;
      _trailCurve = Interval(wait / (wait + settle), 1, curve: _ease);
      (_trail ??= AnimationController(vsync: this))
        ..duration = Duration(milliseconds: wait + settle)
        ..forward(from: 0);
    } else {
      _trail?.value = 1;
    }
  }

  @override
  void dispose() {
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
    final fill = widget.fill;
    final shown = widget.text.trim().isEmpty ? '♪' : widget.text;

    final scale = isActive ? _activeScale : (distance == 1 ? 0.99 : 0.965);
    // Dimming is done in the text colour, not with a layer per line. While
    // it fills, the active line's unsung words wait at a readable grey.
    final opacity = isActive
        ? (fill == null ? 1.0 : 0.42)
        : 0.44 * (distance == 1 ? 0.58 : (isPast ? 0.38 : 0.30));
    final blur =
        isActive || widget.browsing || relative == null || distance > _blurReach
        ? 0.0
        : math.min(distance, 4) * 1.6;
    final shift = isActive ? -3.5 : (isPast ? -1.5 : 3.5);
    final trail = _trail;
    final glow = [
      Shadow(color: Colors.white.withValues(alpha: 0.50), blurRadius: 8),
    ];

    final text = Stack(
      children: [
        AnimatedDefaultTextStyle(
          duration: timed(620),
          curve: _ease,
          style: widget.style.copyWith(
            color: Colors.white.withValues(alpha: opacity),
            shadows: fill == null && isActive ? glow : const [],
          ),
          child: Text(shown),
        ),
        if (fill != null)
          // The lit words, fading away once the line has been sung.
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedOpacity(
                  opacity: isActive ? 1 : 0,
                  duration: timed(620),
                  curve: _ease,
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: LyricFill(
                      text: shown,
                      style: widget.style.copyWith(
                        color: Colors.white,
                        shadows: glow,
                      ),
                      units: fill.units,
                      position: fill.position,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final row = TweenAnimationBuilder<double>(
      tween: Tween(end: blur),
      duration: timed(620),
      curve: _ease,
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
        duration: timed(760),
        curve: _ease,
        builder: (context, dy, child) => trail == null
            ? Transform.translate(offset: Offset(0, dy), child: child)
            : AnimatedBuilder(
                animation: trail,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    dy + _trailFrom * (1 - _trailCurve.transform(trail.value)),
                  ),
                  child: child,
                ),
                child: child,
              ),
        child: AnimatedScale(
          scale: scale,
          alignment: start,
          duration: timed(760),
          curve: _ease,
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
