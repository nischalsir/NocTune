import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_profile.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/motion.dart';
import '../../core/theme/flex_type.dart';
import '../../data/models/track.dart';
import '../playback/noc_audio_handler.dart';
import '../playback/player_colors.dart';
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
                            : context.playerInk.withValues(alpha: 0.90),
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
                        foreground: context.playerInk.withValues(alpha: 0.90),
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
          SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              color: context.playerInk,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Finding lyrics…',
            style: FlexType.bodyLarge.copyWith(
              color: context.playerInk.withValues(alpha: 0.70),
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
              color: context.playerInk.withValues(alpha: 0.90),
            ),
            const SizedBox(height: 14),
            Text(
              failed ? "Couldn't read the lyrics" : 'No lyrics',
              textAlign: TextAlign.center,
              style: FlexType.headlineSmall.copyWith(color: context.playerInk),
            ),
            const SizedBox(height: 14),
            Text(
              failed
                  ? 'The lyrics stored with this track could not be opened.'
                  : 'No lyrics were found in this track or beside it. You '
                        'can add them from an .lrc or text file.',
              textAlign: TextAlign.center,
              style: FlexType.bodyMedium.copyWith(
                color: context.playerInk.withValues(alpha: 0.70),
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
                color: context.playerInk.withValues(alpha: 0.90),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Lyrics not time-synced',
                  style: FlexType.labelSmall.copyWith(
                    color: context.playerInk.withValues(alpha: 0.70),
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
              ).copyWith(color: context.playerInk.withValues(alpha: 0.94)),
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

// How the list and its lines move when the line being sung changes.
//
// The list is carried to the new line by a spring that never overshoots:
// quick away, about half way after 150 ms, at rest within 600 ms. The lines
// below the new one are on softer springs, softer the further down they are,
// so they trail behind the list and catch up one after another. Nothing is
// ever moved in a single step.
const _followFrequency = 11.4;
const _followTime = Duration(milliseconds: 1000);
// A line change's trailing has died away by now.
const _trailTime = Duration(milliseconds: 1400);
// The most of a move that lines trail by, so a long jump doesn't fling them.
const _trailMost = 160.0;

/// The spring of a line [below] the one being sung: the same as the list's
/// for the line right under it, softer from there down.
double _trailFrequency(int below) =>
    math.max(6.0, _followFrequency - 1.45 * (below - 1));

/// A line change the list is following: when it began, how much further the
/// list was sent, and which line it went to.
typedef _Step = ({Duration at, double distance, int active});

/// Tells the lines that trail to redraw, frame by frame.
class _Frames extends ChangeNotifier {
  Duration time = Duration.zero;

  void show(Duration frame) {
    time = frame;
    notifyListeners();
  }
}

/// Timestamped lyrics that follow playback.
///
/// The list is built once. Each line watches which line is being sung and
/// redraws itself only when its own look changes, so a line change touches
/// a handful of rows instead of rebuilding the whole song. Every line is its
/// own layer, so the word fill, which repaints on every frame, redraws
/// nothing but itself.
class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({
    super.key,
    required this.trackId,
    required this.lyrics,
    required this.scale,
  });

  final int trackId;
  final Lyrics lyrics;
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

  // The spring carrying the list, kept so the next one can set off at the
  // speed this one has.
  ({Duration at, double distance, SpringCurve curve})? _glide;
  // The frame callback that will start the next one, if one is waiting.
  int? _followFrame;
  // Where the list was last sent.
  double? _sentTo;
  // The line changes whose trailing lines are still catching up.
  final _steps = <_Step>[];
  final _trail = _Frames();

  /// True while the user moves the list by hand. The lines come into focus
  /// so they can be read.
  final _browsing = ValueNotifier(false);

  late List<GlobalKey> _keys = _makeKeys();
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The line being sung, or -1 before the first.
  final _active = ValueNotifier(-1);

  // The playback position for the word fill, on every frame. The player
  // reports it twenty times a second; between reports this runs on from the
  // last one, so the fill moves at the screen's own refresh rate.
  final _clock = ValueNotifier(Duration.zero);
  late final _frames = createTicker((_) => _onFrame());
  final _sinceReport = Stopwatch();
  Duration _reported = Duration.zero;
  int _offsetMs = 0;
  bool _playing = false;
  bool _sweeping = false;

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

  void _onFrame() {
    _tick();
    if (_steps.isEmpty) return;
    final now = WidgetsBinding.instance.currentFrameTimeStamp;
    _steps.removeWhere((step) => now - step.at > _trailTime);
    _trail.show(now);
    _syncFrames();
  }

  /// Frames are needed while the fill sweeps and while lines trail.
  void _syncFrames() {
    final needed = (_sweeping && _playing) || _steps.isNotEmpty;
    if (needed == _frames.isActive) return;
    needed ? _frames.start() : _frames.stop();
  }

  @override
  void initState() {
    super.initState();
    _reported = ref.read(lyricsPositionProvider).value ?? Duration.zero;
    _offsetMs = ref.read(lyricsOffsetOfProvider(widget.trackId));
    _sinceReport.start();
    _active.value = _indexAt(ref.read(lyricsPositionProvider), _offsetMs);
    // Opens on the line being sung rather than at the top.
    _follow(_active.value, animate: false);
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
    _cancelFollow();
    _frames.dispose();
    _trail.dispose();
    _browsing.dispose();
    _clock.dispose();
    _active.dispose();
    super.dispose();
  }

  /// The line being sung at [position], shifted by the track's saved
  /// timing correction.
  int _indexAt(AsyncValue<Duration> position, int offsetMs) =>
      widget.lyrics.indexAt(
        (position.value ?? Duration.zero) + Duration(milliseconds: offsetMs),
      );

  void _setActive(int index) {
    if (index == _active.value) return;
    _active.value = index;
    _follow(index);
  }

  /// How fast the list is still moving at [now], in pixels a second.
  double _glideSpeed(Duration now) {
    final glide = _glide;
    if (glide == null) return 0;
    final t = (now - glide.at).inMicroseconds / _followTime.inMicroseconds;
    if (t < 0 || t >= 1) return 0;
    return glide.distance * glide.curve.speedAt(t);
  }

  /// How far below its place line [index] is drawn at the moment, while it
  /// catches up with the list.
  double _trailOf(int index) {
    var offset = 0.0;
    for (final step in _steps) {
      final below = index - step.active;
      if (below < 2) continue;
      final seconds =
          (_trail.time - step.at).inMicroseconds /
          Duration.microsecondsPerSecond;
      offset +=
          step.distance *
          (springSettle(_followFrequency, seconds) -
              springSettle(_trailFrequency(below), seconds));
    }
    return offset;
  }

  void _cancelFollow() {
    final frame = _followFrame;
    if (frame != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(frame);
    }
    _followFrame = null;
  }

  /// Leaves the list where it is: nothing in flight, nothing trailing.
  void _letGo() {
    _glide = null;
    _sentTo = null;
    if (_steps.isEmpty) return;
    _steps.clear();
    _trail.show(_trail.time);
    _syncFrames();
  }

  /// Brings the active line to a third of the way down, unless the user has
  /// just been scrolling.
  void _follow(int index, {bool animate = true}) {
    if (index < 0 || index >= _keys.length) return;
    if (DateTime.now().difference(_userScrolledAt) < _handsOff) return;
    _cancelFollow();
    // Started at the top of the next frame, where an animation gets under
    // way in that same frame. Started after a frame, a move that replaces
    // one still running would stand still for a frame first.
    _followFrame = WidgetsBinding.instance.scheduleFrameCallback((now) {
      _followFrame = null;
      final target = _keys[index].currentContext;
      if (!mounted || target == null) return;
      final line = target.findRenderObject()!;
      final position = Scrollable.of(target).position;
      final to = RenderAbstractViewport.of(line)
          .getOffsetToReveal(line, 1 / 3)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (!animate || MediaQuery.disableAnimationsOf(context)) {
        _letGo();
        _sentTo = to;
        position.jumpTo(to);
        return;
      }
      final distance = to - position.pixels;
      final further = to - (_sentTo ?? position.pixels);
      _sentTo = to;
      if (distance.abs() < 0.5) return;
      // If the list is still on its way to the line before, it is not
      // stopped and started again: the spring is let go at the speed the
      // list already has.
      final curve = SpringCurve(
        frequency: _followFrequency,
        seconds: _followTime.inMicroseconds / Duration.microsecondsPerSecond,
        velocity: _glideSpeed(now) / distance,
      );
      _glide = (at: now, distance: distance, curve: curve);
      _steps.add((
        at: now,
        distance: further.clamp(-_trailMost, _trailMost).toDouble(),
        active: index,
      ));
      _trail.time = now;
      _syncFrames();
      position.animateTo(to, duration: _followTime, curve: curve);
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
      _letGo();
      _setBrowsing(true);
    } else if (notification is ScrollEndNotification) {
      _setBrowsing(false);
    }
    return false;
  }

  void _setBrowsing(bool browsing) {
    if (_browsing.value == browsing) return;
    // A scroll can end while the page is being laid out, when nothing may
    // be rebuilt: the lines are told once that frame is done.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _browsing.value = browsing;
      });
    } else {
      _browsing.value = browsing;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    // Out-of-focus lines are left out on devices short of memory.
    final soften = ref.watch(deviceTierProvider) != DeviceTier.low;
    ref
      ..listen(lyricsPositionProvider, (_, position) {
        _reported = position.value ?? _reported;
        _sinceReport
          ..reset()
          ..start();
        _tick();
        _setActive(_indexAt(position, _offsetMs));
      })
      ..listen(lyricsOffsetOfProvider(widget.trackId), (_, offset) {
        _offsetMs = offset;
        _tick();
        _setActive(_indexAt(ref.read(lyricsPositionProvider), offset));
      });

    // With reduced motion the line lights up at once instead of filling.
    final sweep = !MediaQuery.disableAnimationsOf(context);
    _playing = playing;
    _sweeping = sweep;
    _syncFrames();

    final style = FlexType.custom(
      size: 30 * widget.scale,
      lineHeight: 30 * widget.scale * 1.38,
      weight: 700,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
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
                      // Its own layer: scrolling moves it, and redraws none
                      // of the lines.
                      child: RepaintBoundary(
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
                                  index: index,
                                  line: line,
                                  nextLineAt: index + 1 < lines.length
                                      ? lines[index + 1].time
                                      : null,
                                  style: style,
                                  textWidth: textWidth,
                                  active: _active,
                                  clock: _clock,
                                  sweep: sweep,
                                  soften: soften,
                                  browsing: _browsing,
                                  trail: _trail,
                                  trailOf: _trailOf,
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
/// being sung: that one is enlarged and lights up word by word; the further
/// away a line is, the dimmer and the more out of focus it gets.
///
/// Its size on the page never changes, so the lines around it don't move
/// when it becomes active. Everything that changes is a transform or a
/// brightness, moved from where it is by a spring or an ease, which the
/// screen can redraw on every frame. Nothing changes in a single step.
class _LyricRow extends StatefulWidget {
  const _LyricRow({
    required this.index,
    required this.line,
    required this.nextLineAt,
    required this.style,
    required this.textWidth,
    required this.active,
    required this.clock,
    required this.sweep,
    required this.soften,
    required this.browsing,
    required this.trail,
    required this.trailOf,
    required this.onTap,
  });

  final int index;
  final LyricLine line;
  final Duration? nextLineAt;
  final TextStyle style;
  final double textWidth;

  /// The index of the line being sung.
  final ValueListenable<int> active;

  /// The playback position, frame by frame, for the word fill.
  final ValueListenable<Duration> clock;

  /// Whether the active line fills word by word, or lights up at once.
  final bool sweep;

  /// Whether lines away from the active one go out of focus.
  final bool soften;

  /// Whether the user is moving the list by hand.
  final ValueListenable<bool> browsing;

  /// Redraws the line while it trails behind the list, by [trailOf].
  final Listenable trail;
  final double Function(int index) trailOf;
  final VoidCallback? onTap;

  @override
  State<_LyricRow> createState() => _LyricRowState();
}

class _LyricRowState extends State<_LyricRow> {
  // Beyond this many lines from the active one, every line looks the same.
  static const _reach = 10;
  // The line grows with a little overshoot and settles; its small step up or
  // down settles without one.
  static const _grow = SpringCurve(
    frequency: 16.1,
    damping: 0.62,
    seconds: 0.7,
  );
  static const _step = SpringCurve(
    frequency: 14.1,
    damping: 0.82,
    seconds: 0.6,
  );
  static const _fade = Curves.fastOutSlowIn;
  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 7);
  // For lines that trail nothing: a listenable that never calls.
  static const _still = AlwaysStoppedAnimation<double>(0);

  /// Lines from the active one, limited to [_reach] either way: negative
  /// above, positive below. Null before the first line is reached.
  int? _relative;

  /// Whether the line is changing size at the moment.
  bool _scaling = false;

  static double _scaleAt(int? relative) => switch (relative?.abs()) {
    0 => _activeScale,
    1 => 0.99,
    _ => 0.965,
  };

  int? _relativeNow() {
    final active = widget.active.value;
    return active < 0
        ? null
        : (widget.index - active).clamp(-_reach, _reach).toInt();
  }

  @override
  void initState() {
    super.initState();
    _relative = _relativeNow();
    widget.active.addListener(_onActiveChanged);
    widget.browsing.addListener(_onBrowsingChanged);
  }

  @override
  void didUpdateWidget(_LyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      oldWidget.active.removeListener(_onActiveChanged);
      widget.active.addListener(_onActiveChanged);
    }
    if (oldWidget.browsing != widget.browsing) {
      oldWidget.browsing.removeListener(_onBrowsingChanged);
      widget.browsing.addListener(_onBrowsingChanged);
    }
  }

  void _onActiveChanged() {
    final relative = _relativeNow();
    if (relative == _relative) return;
    setState(() {
      if (_scaleAt(relative) != _scaleAt(_relative) &&
          !MediaQuery.disableAnimationsOf(context)) {
        _scaling = true;
      }
      _relative = relative;
    });
  }

  void _onBrowsingChanged() {
    // Only lines near enough to be out of focus have anything to change.
    final relative = _relative;
    if (relative != null && relative != 0 && relative.abs() < _reach) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.active.removeListener(_onActiveChanged);
    widget.browsing.removeListener(_onBrowsingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final relative = _relative;
    final isActive = relative == 0;
    final distance = relative?.abs() ?? _reach;
    final isPast = relative != null && relative < 0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Duration timed(int ms) =>
        reduceMotion ? Duration.zero : Duration(milliseconds: ms);
    final start = AlignmentDirectional.centerStart.resolve(
      Directionality.of(context),
    );
    final text = widget.line.text;
    final shown = text.trim().isEmpty ? '♪' : text;
    // The line being sung fills as it goes; the one just sung keeps its
    // fill while it fades back.
    final filling = widget.sweep && (relative == 0 || relative == -1);

    final scale = _scaleAt(relative);
    // While it fills, the active line's unsung words wait at a readable
    // grey.
    final brightness = isActive
        ? (widget.sweep ? 0.42 : 1.0)
        : 0.44 * (distance == 1 ? 0.58 : (isPast ? 0.38 : 0.30));
    // Depth of field: the further from the line being sung, the softer.
    // Lines come back into focus while the user is browsing, and lines too
    // far away to be on screen are never blurred at all.
    final softness =
        !widget.soften ||
            widget.browsing.value ||
            relative == null ||
            distance >= _reach
        ? 0
        : math.min(distance, 4);
    final shift = isActive ? -3.5 : (isPast ? -1.5 : 3.5);
    // Lines at and just below the active one may be trailing.
    final trailing = relative != null && relative >= 0 && relative < _reach;

    final words = Stack(
      children: [
        _LyricText(
          text: shown,
          style: widget.style,
          padding: _padding,
          softness: softness,
          brightness: brightness,
          glow: !widget.sweep && isActive,
          animate: !reduceMotion,
        ),
        if (filling)
          // The lit words, fading away once the line has been sung.
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedOpacity(
                  opacity: isActive ? 1 : 0,
                  duration: timed(320),
                  curve: _fade,
                  child: Padding(
                    padding: _padding,
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      // Repaints on every frame, and only itself.
                      child: RepaintBoundary(
                        child: LyricFill(
                          text: shown,
                          style: widget.style.copyWith(
                            color: context.playerInk,
                            shadows: _LyricTextState.glowOf(context),
                          ),
                          units: lyricUnits(
                            widget.line,
                            nextLineAt: widget.nextLineAt,
                          ),
                          position: widget.clock,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final row = TweenAnimationBuilder<double>(
      tween: Tween(end: shift),
      duration: timed(600),
      curve: _step,
      builder: (context, dy, child) => ListenableBuilder(
        listenable: trailing ? widget.trail : _still,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, dy + (trailing ? widget.trailOf(widget.index) : 0)),
          child: child,
        ),
        child: child,
      ),
      child: AnimatedScale(
        scale: scale,
        alignment: start,
        duration: timed(700),
        curve: _grow,
        // While it changes size the line is scaled as a picture. Drawing the
        // text itself at a new size on every frame makes the letters jitter
        // and has every glyph drawn afresh each time. At rest it is text
        // again, and sharp.
        filterQuality: _scaling ? FilterQuality.low : null,
        onEnd: () {
          if (_scaling) setState(() => _scaling = false);
        },
        // Its own layer, so moving or resizing the line redraws nothing.
        child: RepaintBoundary(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.textWidth + _padding.horizontal,
              ),
              child: words,
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

/// A lyric line's text, at a given brightness and sharpness.
///
/// Lines away from the one being sung are out of focus. Blurring text on
/// every frame is costly, so a soft line is blurred once and kept as a
/// picture ([_SoftText]). When its softness changes, the new picture comes
/// up over the old one and only then does the old one go, so the two never
/// add up to a line brighter or dimmer than it should be.
class _LyricText extends StatefulWidget {
  const _LyricText({
    required this.text,
    required this.style,
    required this.padding,
    required this.softness,
    required this.brightness,
    required this.glow,
    required this.animate,
  });

  final String text;
  final TextStyle style;
  final EdgeInsets padding;

  /// 0 is sharp; each step up is further out of focus.
  final int softness;
  final double brightness;

  /// A soft halo around sharp text.
  final bool glow;
  final bool animate;

  @override
  State<_LyricText> createState() => _LyricTextState();
}

class _LyricTextState extends State<_LyricText>
    with SingleTickerProviderStateMixin {
  /// A soft light around the line being sung. Only on the dark player: on
  /// the light one it would only smudge the dark text.
  static List<Shadow>? glowOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const [Shadow(color: Color(0x80FFFFFF), blurRadius: 8)]
      : null;

  late final _mix = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );
  late final _arriving = CurvedAnimation(
    parent: _mix,
    curve: const Interval(0, 0.5, curve: Curves.fastOutSlowIn),
  );
  late final _stillThere = CurvedAnimation(
    parent: _mix,
    curve: const Interval(0.5, 1, curve: Curves.fastOutSlowIn),
  );
  late final _leaving = ReverseAnimation(_stillThere);

  /// The softness being left, while the old and new pictures are mixed.
  int? _from;

  @override
  void initState() {
    super.initState();
    _mix.addStatusListener((status) {
      if (status == AnimationStatus.completed && _from != null) {
        setState(() => _from = null);
      }
    });
  }

  @override
  void didUpdateWidget(_LyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.softness == widget.softness) return;
    if (widget.animate) {
      _from = oldWidget.softness;
      _mix.forward(from: 0);
    } else {
      _from = null;
      _mix.value = 1;
    }
  }

  @override
  void dispose() {
    _arriving.dispose();
    _stillThere.dispose();
    _mix.dispose();
    super.dispose();
  }

  Widget _layer(int softness, double white) => softness == 0
      ? Padding(
          padding: widget.padding,
          child: Text(
            widget.text,
            style: widget.style.copyWith(
              color: context.playerInk.withValues(alpha: white),
              shadows: widget.glow ? glowOf(context) : null,
            ),
          ),
        )
      : _SoftText(
          text: widget.text,
          style: widget.style,
          padding: widget.padding,
          sigma: 0.92 * softness + 0.17,
        );

  @override
  Widget build(BuildContext context) {
    final from = _from;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.brightness),
      duration: widget.animate
          ? const Duration(milliseconds: 320)
          : Duration.zero,
      curve: Curves.fastOutSlowIn,
      builder: (context, brightness, _) {
        // One sharp layer at full brightness is simply drawn. Anything else
        // is drawn solid and dimmed as a whole: dimmed through its colour,
        // letters that overlap, as Devanagari ones do along their top
        // line, would show lighter seams where they cross.
        final inColour =
            from == null && widget.softness == 0 && brightness >= 1;
        return Opacity(
          opacity: inColour ? 1 : brightness,
          child: Stack(
            children: [
              if (from != null)
                FadeTransition(
                  key: ValueKey(from),
                  opacity: _leaving,
                  child: ExcludeSemantics(child: _layer(from, 1)),
                ),
              FadeTransition(
                key: ValueKey(widget.softness),
                opacity: from == null ? kAlwaysCompleteAnimation : _arriving,
                child: _layer(widget.softness, inColour ? brightness : 1),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Text out of focus: blurred once and kept as a picture, which is drawn
/// again only when the text, its style or its size changes.
class _SoftText extends StatefulWidget {
  const _SoftText({
    required this.text,
    required this.style,
    required this.padding,
    required this.sigma,
  });

  final String text;
  final TextStyle style;

  /// Room around the text for the blur to spread into.
  final EdgeInsets padding;
  final double sigma;

  @override
  State<_SoftText> createState() => _SoftTextState();
}

class _SoftTextState extends State<_SoftText> {
  final _picture = SnapshotController(allowSnapshotting: true);

  @override
  void didUpdateWidget(_SoftText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.padding != widget.padding ||
        oldWidget.sigma != widget.sigma) {
      _picture.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The text size or the reading direction changed.
    _picture.clear();
  }

  @override
  void dispose() {
    _picture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read here so that a change to either draws the picture again.
    MediaQuery.textScalerOf(context);
    Directionality.of(context);
    return SnapshotWidget(
      controller: _picture,
      autoresize: true,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: widget.sigma,
          sigmaY: widget.sigma,
          tileMode: TileMode.decal,
        ),
        child: Padding(
          padding: widget.padding,
          child: Text(
            widget.text,
            style: widget.style.copyWith(color: context.playerInk),
          ),
        ),
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
          color: context.playerShade.withValues(alpha: 0.35),
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
                      color: context.playerInk.withValues(alpha: 0.90),
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
                      color: context.playerInk.withValues(alpha: 0.70),
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
                      color: context.playerInk.withValues(alpha: 0.95),
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
      color: context.playerInk.withValues(alpha: 0.85),
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
            SizedBox.square(
              dimension: 56,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: context.playerInk,
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
