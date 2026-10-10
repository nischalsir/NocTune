import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/flex_type.dart';

/// The seek bar of the player and the lyrics view, for a dark backdrop.
///
/// As a wave, the played part is three layered waves of tinted glass that
/// drift while music plays and flatten while the thumb is held. As a bar it
/// is a thick rounded track with a tall handle and a dot marking the end.
///
/// Either way the handle follows the finger and the player seeks once, on
/// release; the position reported to assistive technology is the real one.
class PlayerSeekBar extends ConsumerStatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.duration,
    required this.wave,
    this.showTimes = true,
  });

  final Duration duration;

  /// Draw the animated wave rather than the plain bar.
  final bool wave;

  /// Show time played and time left beneath the bar.
  final bool showTimes;

  @override
  ConsumerState<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends ConsumerState<PlayerSeekBar>
    with SingleTickerProviderStateMixin {
  // One loop long enough for the three layers (2.4 s, 1.8 s and 1.3 s per
  // cycle) to drift independently without a visible seam.
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 93600),
  );

  /// Where the thumb is while a finger holds it, as a fraction; null when
  /// the bar is following playback.
  double? _drag;

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  void _syncDrift(bool active) {
    if (active == _drift.isAnimating) return;
    active ? _drift.repeat() : _drift.stop();
  }

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  void _commit() {
    final drag = _drag;
    if (drag == null) return;
    ref.read(audioHandlerProvider).seek(widget.duration * drag);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.duration;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final enabled = total > Duration.zero;
    final live = enabled
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final fraction = _drag ?? live;
    final dragging = _drag != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncDrift(widget.wave && playing && !dragging && !reduceMotion);

    final shown = total * fraction;
    // Assistive technology moves the position ten seconds at a time.
    final forward = _clamp(position + const Duration(seconds: 10), total);
    final back = _clamp(position - const Duration(seconds: 10), total);
    String spoken(Duration at) =>
        '${formatDuration(at)} of ${formatDuration(total)}';
    final primary = _luminous(scheme.primary, 0.60);

    final bar = Semantics(
      slider: true,
      label: 'Playback position',
      value: spoken(shown),
      increasedValue: enabled ? spoken(forward) : null,
      decreasedValue: enabled ? spoken(back) : null,
      onIncrease: enabled
          ? () => ref.read(audioHandlerProvider).seek(forward)
          : null,
      onDecrease: enabled
          ? () => ref.read(audioHandlerProvider).seek(back)
          : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          void hold(Offset at) =>
              setState(() => _drag = _fractionAt(at, width));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => hold(d.localPosition) : null,
            onTapUp: enabled ? (_) => _commit() : null,
            onTapCancel: () => setState(() => _drag = null),
            onHorizontalDragStart: enabled
                ? (d) => hold(d.localPosition)
                : null,
            onHorizontalDragUpdate: enabled
                ? (d) => hold(d.localPosition)
                : null,
            onHorizontalDragEnd: enabled ? (_) => _commit() : null,
            onHorizontalDragCancel: () => setState(() => _drag = null),
            // The wave moves on every frame; nothing else is redrawn for it.
            child: RepaintBoundary(
              child: widget.wave
                  ? TweenAnimationBuilder<double>(
                      // Waves sink to a ripple while the thumb is held.
                      tween: Tween(end: dragging ? 0.0 : 1.0),
                      duration: const Duration(milliseconds: 180),
                      builder: (context, calm, _) => CustomPaint(
                        size: Size(width, 50),
                        painter: _WavePainter(
                          drift: _drift,
                          fraction: fraction,
                          calm: calm,
                          primary: primary,
                          secondary: _luminous(scheme.secondary, 0.52),
                          tertiary: _luminous(scheme.tertiary, 0.48),
                        ),
                      ),
                    )
                  : CustomPaint(
                      size: Size(width, 44),
                      painter: _BarPainter(
                        fraction: fraction,
                        color: enabled
                            ? primary
                            : Colors.white.withValues(alpha: 0.34),
                      ),
                    ),
            ),
          );
        },
      ),
    );
    if (!widget.showTimes) return bar;

    final timeStyle = FlexType.custom(size: 12, lineHeight: 16, weight: 480)
        .copyWith(
          color: Colors.white.withValues(alpha: 0.85),
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bar,
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shown), style: timeStyle),
              // Counts down what is left. Unknown until the length is.
              Text(
                enabled ? '−${formatDuration(total - shown)}' : '–:––',
                style: timeStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Duration _clamp(Duration value, Duration max) =>
    value < Duration.zero ? Duration.zero : (value > max ? max : value);

/// [color] made light enough to read on a dark backdrop.
Color _luminous(Color color, double minLightness) {
  final hsl = HSLColor.fromColor(color);
  return hsl.lightness >= minLightness
      ? color
      : hsl.withLightness(minLightness).toColor();
}

/// A thick rounded track split around a tall handle, with a dot at the end.
class _BarPainter extends CustomPainter {
  const _BarPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  static const _trackHeight = 14.0;
  static const _thumbWidth = 5.0;
  static const _thumbHeight = 38.0;
  static const _clearance = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const radius = Radius.circular(_trackHeight / 2);
    final thumbX = (fraction * size.width)
        .clamp(
          _thumbWidth / 2,
          math.max(_thumbWidth / 2, size.width - _thumbWidth / 2),
        )
        .toDouble();
    final activeEnd = (thumbX - _clearance).clamp(0.0, size.width);
    final inactiveStart = (thumbX + _clearance).clamp(0.0, size.width);
    final top = centerY - _trackHeight / 2;

    if (activeEnd > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, activeEnd, _trackHeight),
          radius,
        ),
        Paint()..color = color,
      );
    }
    if (inactiveStart < size.width) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(inactiveStart, top, size.width, top + _trackHeight),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
      final endX = size.width - _trackHeight / 2;
      if (endX > inactiveStart + 4) {
        canvas.drawCircle(
          Offset(endX, centerY),
          2,
          Paint()..color = color.withValues(alpha: 0.86),
        );
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(thumbX, centerY),
          width: _thumbWidth,
          height: _thumbHeight,
        ),
        const Radius.circular(_thumbWidth / 2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction || old.color != color;
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.drift,
    required this.fraction,
    required this.calm,
    required this.primary,
    required this.secondary,
    required this.tertiary,
  }) : super(repaint: drift);

  final Animation<double> drift;
  final double fraction;

  /// 1 while following playback, 0 while the thumb is held.
  final double calm;
  final Color primary;
  final Color secondary;
  final Color tertiary;

  static const _trackThickness = 4.5;
  static const _thumbRadius = 7.5;
  static const _transition = 44.0;
  static const _step = 1.5;
  static const _restingAmplitude = 1.2;
  // Seconds in one loop of the drift controller.
  static const _loopSeconds = 93.6;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2 + 7;
    final thumbX = (fraction * size.width).clamp(0.0, size.width);
    final half = _trackThickness / 2;
    final seconds = drift.value * _loopSeconds;

    canvas.drawLine(
      Offset(thumbX, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..strokeWidth = _trackThickness
        ..strokeCap = StrokeCap.round,
    );

    if (thumbX > 0) {
      void layer({
        required double wavelength,
        required double amplitude,
        required double phase,
        required Color color,
        required double topAlpha,
        required double bottomAlpha,
        required double stroke,
      }) {
        final amp = _restingAmplitude + (amplitude - _restingAmplitude) * calm;
        final top = centerY - half;
        final bottom = centerY + half;
        final fade = math.min(_transition, thumbX * 0.48);
        final filled = Path()..moveTo(0, bottom);
        final contour = Path();
        var first = true;
        for (var x = 0.0; ; x += _step) {
          final at = math.min(x, thumbX);
          // The wave swells in from the start and settles before the thumb.
          final envelope = fade <= 0
              ? 1.0
              : _smoother(at / fade) * _smoother((thumbX - at) / fade);
          final angle = at * 2 * math.pi / wavelength - phase;
          final y = top - (0.5 + 0.5 * math.sin(angle)) * amp * envelope;
          filled.lineTo(at, y);
          first ? contour.moveTo(at, y) : contour.lineTo(at, y);
          first = false;
          if (at >= thumbX) break;
        }
        filled
          ..lineTo(thumbX, bottom)
          ..close();
        final bounds = Rect.fromLTRB(0, top - amp, thumbX, bottom);
        canvas
          ..drawPath(
            filled,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: topAlpha),
                  color.withValues(alpha: bottomAlpha),
                ],
              ).createShader(bounds),
          )
          ..drawPath(
            contour,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = Color.lerp(
                color,
                Colors.white,
                0.35,
              )!.withValues(alpha: topAlpha),
          );
      }

      // Back to front: a deep ambient layer, a frosted middle, a bright
      // foreground.
      layer(
        wavelength: 160,
        amplitude: 13,
        phase: seconds * 2 * math.pi / 2.4 + 2.2,
        color: tertiary,
        topAlpha: 0.42,
        bottomAlpha: 0.32,
        stroke: 1.0,
      );
      layer(
        wavelength: 125,
        amplitude: 10,
        phase: seconds * 2 * math.pi / 1.8 + 1.2,
        color: secondary,
        topAlpha: 0.72,
        bottomAlpha: 0.62,
        stroke: 1.2,
      );
      layer(
        wavelength: 95,
        amplitude: 7.5,
        phase: seconds * 2 * math.pi / 1.3,
        color: primary,
        topAlpha: 0.98,
        bottomAlpha: 0.92,
        stroke: 1.6,
      );
    }

    canvas.drawCircle(
      Offset(thumbX, centerY),
      _thumbRadius,
      Paint()..color = primary,
    );
  }

  static double _smoother(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * x * (x * (x * 6 - 15) + 10);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.fraction != fraction ||
      old.calm != calm ||
      old.primary != primary ||
      old.secondary != secondary ||
      old.tertiary != tertiary;
}
