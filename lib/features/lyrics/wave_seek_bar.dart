import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';

/// The seek bar of the lyrics view: the played part is three layered waves
/// of tinted glass that drift while music plays, the rest a flat line. The
/// waves flatten while the thumb is dragged. Made for a dark backdrop.
///
/// The position it reports to assistive technology, and the one it seeks to,
/// is the real playback position.
class WaveSeekBar extends ConsumerStatefulWidget {
  const WaveSeekBar({super.key, required this.duration});

  final Duration duration;

  @override
  ConsumerState<WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends ConsumerState<WaveSeekBar>
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
    _syncDrift(playing && !dragging && !reduceMotion);

    final shown = total * fraction;
    // Assistive technology moves the position ten seconds at a time.
    final forward = _clamp(position + const Duration(seconds: 10), total);
    final back = _clamp(position - const Duration(seconds: 10), total);
    String spoken(Duration at) =>
        '${formatDuration(at)} of ${formatDuration(total)}';
    return Semantics(
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
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (d) => setState(
                    () => _drag = _fractionAt(d.localPosition, width),
                  )
                : null,
            onTapUp: enabled ? (_) => _commit() : null,
            onTapCancel: () => setState(() => _drag = null),
            onHorizontalDragStart: enabled
                ? (d) => setState(
                    () => _drag = _fractionAt(d.localPosition, width),
                  )
                : null,
            onHorizontalDragUpdate: enabled
                ? (d) => setState(
                    () => _drag = _fractionAt(d.localPosition, width),
                  )
                : null,
            onHorizontalDragEnd: enabled ? (_) => _commit() : null,
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: TweenAnimationBuilder<double>(
              // Waves sink to a ripple while the thumb is held.
              tween: Tween(end: dragging ? 0.0 : 1.0),
              duration: const Duration(milliseconds: 180),
              builder: (context, calm, _) => CustomPaint(
                size: Size(width, 50),
                painter: _WavePainter(
                  drift: _drift,
                  fraction: fraction,
                  calm: calm,
                  primary: _luminous(scheme.primary, 0.60),
                  secondary: _luminous(scheme.secondary, 0.52),
                  tertiary: _luminous(scheme.tertiary, 0.48),
                ),
              ),
            ),
          );
        },
      ),
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
