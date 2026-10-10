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
import '../settings/settings_controller.dart';
import 'lyrics.dart';
import 'lyrics_offset.dart';
import 'lyrics_source.dart';
import 'wave_seek_bar.dart';

/// The lyrics view of the player, for a dark backdrop: the lyrics fill the
/// space, and beneath them sit the lyric actions, a seek bar and the
/// transport buttons.
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

  LyricsKey get _key => (trackId: widget.track.id, uri: widget.track.uri);

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await importLyricsFor(widget.track, ref);
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

  Future<void> _removeImported() async {
    await ref
        .read(libraryRepositoryProvider)
        .removeImportedLyrics(widget.track.id);
    ref.invalidate(lyricsProvider(_key));
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(lyricsProvider(_key));
    final scale = ref.watch(settingsProvider.select((s) => s.lyricsScale));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final found = loaded.value;

    final Widget content;
    if (loaded.isLoading && found == null) {
      content = const _Loading(key: ValueKey('loading'));
    } else if (found == null) {
      content = _Empty(
        key: const ValueKey('empty'),
        failed: loaded.hasError,
        onImport: _import,
      );
    } else if (found.lyrics.synced) {
      content = _SyncedLyrics(
        // A new track starts at the top with fresh state.
        key: ValueKey('synced-${widget.track.id}'),
        trackId: widget.track.id,
        lyrics: found.lyrics,
        origin: found.origin,
        scale: scale,
      );
    } else {
      content = _PlainLyrics(
        key: ValueKey('plain-${widget.track.id}'),
        lyrics: found.lyrics,
        scale: scale,
      );
    }

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
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
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
                  _LyricsMenuButton(
                    synced: found?.lyrics.synced ?? false,
                    canRemove: found?.origin == LyricsOrigin.imported,
                    onImport: _import,
                    onRemove: _removeImported,
                    onOffset: () =>
                        showLyricsOffsetDialog(context, widget.track.id),
                  ),
                  const SizedBox(width: 10),
                  _GlassCircle(
                    icon: Icons.format_size,
                    label: 'Adjust lyrics text size',
                    iconSize: 22,
                    highlighted: _showSizeSlider || scale != 1,
                    onTap: () =>
                        setState(() => _showSizeSlider = !_showSizeSlider),
                  ),
                  const SizedBox(width: 10),
                  _GlassCircle(
                    icon: widget.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    label: widget.isFullscreen
                        ? 'Exit fullscreen lyrics'
                        : 'Fullscreen lyrics',
                    onTap: widget.onToggleFullscreen,
                  ),
                ],
              ),
              if (!widget.isFullscreen) ...[
                const SizedBox(height: 6),
                WaveSeekBar(duration: widget.duration),
                const SizedBox(height: 6),
                _Transport(duration: widget.duration),
              ],
            ],
          ),
        ),
      ],
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
          Text(
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
        ],
      ),
    );
  }
}

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
          ref.read(playbackPositionProvider),
          ref.read(lyricsOffsetOfProvider(widget.trackId)),
        ),
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
  void _follow(int index) {
    if (index < 0 || index >= _keys.length) return;
    if (DateTime.now().difference(_userScrolledAt) < _handsOff) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[index].currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 1 / 3,
        duration: MediaQuery.disableAnimationsOf(context)
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
    // Rebuilds when the line changes, not on every position tick.
    final active = ref.watch(
      playbackPositionProvider.select((p) => _indexAt(p, offset)),
    );
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    ref.listen(
      playbackPositionProvider.select((p) => _indexAt(p, offset)),
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
            padding: const EdgeInsets.only(bottom: 6),
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
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 26),
                        child: _LyricRow(
                          text: line.text,
                          style: style,
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
          ),
        ],
      ),
    );
  }
}

/// One lyric line. How it looks depends on where it is relative to the line
/// being sung: that one is enlarged, bright and sharp with a soft glow; the
/// further away a line is, the dimmer and softer it gets.
class _LyricRow extends StatefulWidget {
  const _LyricRow({
    required this.text,
    required this.style,
    required this.relative,
    required this.playing,
    required this.browsing,
    required this.onTap,
  });

  final String text;
  final TextStyle style;

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
  // The pulse a line gives as it becomes the active one.
  late final _onset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  // The settle of lines below the active one as the list moves on.
  late final _trail = AnimationController(vsync: this, value: 1);
  double _trailFrom = 0;

  @override
  void didUpdateWidget(_LyricRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final relative = widget.relative;
    if (relative == oldWidget.relative) return;
    final animate = widget.playing && !MediaQuery.disableAnimationsOf(context);
    if (relative == 0 && animate) {
      _onset.forward(from: 0);
    } else {
      _onset.value = 0;
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
      _trail
        ..duration = Duration(milliseconds: wait + settle)
        ..forward(from: 0);
      _trailCurve = Interval(
        wait / (wait + settle),
        1,
        curve: const _Spring(ratio: 0.72, stiffness: 180, seconds: 0.62),
      );
    } else {
      _trail.value = 1;
    }
  }

  Curve _trailCurve = Curves.linear;

  @override
  void dispose() {
    _onset.dispose();
    _trail.dispose();
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

    final scale = isActive ? 1.085 : (distance == 1 ? 0.99 : 0.965);
    final opacity = isActive
        ? 1.0
        : (distance == 1 ? 0.58 : (isPast ? 0.38 : 0.30));
    final blur = isActive || widget.browsing || relative == null
        ? 0.0
        : math.min(distance, 4) * 1.6;
    final shift = isActive ? -3.5 : (isPast ? -1.5 : 3.5);

    final text = AnimatedDefaultTextStyle(
      duration: timed(240),
      curve: Curves.fastOutSlowIn,
      style: widget.style.copyWith(
        color: isActive
            ? Colors.white
            : Colors.white.withValues(alpha: 0.55 * 0.44),
        shadows: [
          Shadow(
            color: Colors.white.withValues(alpha: isActive ? 0.50 : 0),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(widget.text.trim().isEmpty ? '♪' : widget.text),
    );

    final row = AnimatedOpacity(
      opacity: opacity,
      duration: timed(320),
      curve: Curves.fastOutSlowIn,
      child: TweenAnimationBuilder<double>(
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
            animation: Listenable.merge([_onset, _trail]),
            builder: (context, child) {
              final trail =
                  _trailFrom * (1 - _trailCurve.transform(_trail.value));
              final wave = _onset.isAnimating
                  ? math.sin(
                      math.pi * Curves.fastOutSlowIn.transform(_onset.value),
                    )
                  : 0.0;
              return Transform.translate(
                offset: Offset(0, dy + trail),
                child: Transform.scale(
                  scale: 1 + 0.020 * wave,
                  alignment: AlignmentDirectional.centerStart.resolve(
                    Directionality.of(context),
                  ),
                  child: child,
                ),
              );
            },
            child: child,
          ),
          child: AnimatedScale(
            scale: scale,
            alignment: AlignmentDirectional.centerStart.resolve(
              Directionality.of(context),
            ),
            duration: timed(600),
            curve: const _Spring(ratio: 0.62, stiffness: 260, seconds: 0.6),
            child: AnimatedPadding(
              duration: timed(200),
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isActive ? 8 : 6,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
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

/// A round glass button that dips while pressed.
class _GlassCircle extends StatefulWidget {
  const _GlassCircle({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.iconSize = 24,
    this.fill = 0.14,
    this.highlighted = false,
    this.showTooltip = true,
    this.child,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Opacity of the white fill.
  final double fill;

  /// Tints the button with the accent, for a control that is switched on.
  final bool highlighted;

  /// Off for a circle that sits inside something with its own tooltip.
  final bool showTooltip;

  /// Shown instead of the icon.
  final Widget? child;

  @override
  State<_GlassCircle> createState() => _GlassCircleState();
}

class _GlassCircleState extends State<_GlassCircle> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      // An empty message shows no tooltip.
      message: widget.showTooltip ? widget.label : '',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: widget.onTap != null,
        label: widget.label,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed && !reduceMotion ? 0.82 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Material(
              color: widget.highlighted
                  ? primary.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: widget.fill),
              shape: CircleBorder(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                child: SizedBox.square(
                  dimension: widget.size,
                  child: Center(
                    child:
                        widget.child ??
                        Icon(
                          widget.icon,
                          size: widget.iconSize,
                          color: widget.highlighted
                              ? primary
                              : Colors.white.withValues(alpha: 0.92),
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

enum _LyricsAction { import, remove, offset }

/// Where a lyrics file is added or removed and its timing corrected.
class _LyricsMenuButton extends StatelessWidget {
  const _LyricsMenuButton({
    required this.synced,
    required this.canRemove,
    required this.onImport,
    required this.onRemove,
    required this.onOffset,
  });

  final bool synced;
  final bool canRemove;
  final VoidCallback onImport;
  final VoidCallback onRemove;
  final VoidCallback onOffset;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_LyricsAction>(
      tooltip: 'Lyrics options',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (action) => switch (action) {
        _LyricsAction.import => onImport(),
        _LyricsAction.remove => onRemove(),
        _LyricsAction.offset => onOffset(),
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
        if (canRemove)
          const PopupMenuItem(
            value: _LyricsAction.remove,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Remove imported lyrics'),
            ),
          ),
        if (synced)
          const PopupMenuItem(
            value: _LyricsAction.offset,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.timer_outlined),
              title: Text('Lyrics sync offset…'),
            ),
          ),
      ],
      // The menu button owns the tap, the tooltip and the semantics; the
      // circle only draws.
      child: const IgnorePointer(
        child: ExcludeSemantics(
          child: _GlassCircle(
            icon: Icons.more_horiz,
            label: 'Lyrics options',
            onTap: null,
            showTooltip: false,
          ),
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
          _GlassCircle(
            icon: Icons.skip_previous,
            label: 'Previous',
            size: 46,
            onTap: () => handler().skipToPrevious(),
          ),
          const SizedBox(width: 16),
          _GlassCircle(
            icon: playing ? Icons.pause : Icons.play_arrow,
            label: playing ? 'Pause' : 'Play',
            size: 56,
            iconSize: 28,
            fill: 0.18,
            onTap: () => playing ? handler().pause() : handler().play(),
            child: busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          _GlassCircle(
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
