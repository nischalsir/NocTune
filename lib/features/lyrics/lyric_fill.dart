import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'lyrics.dart';

/// A stretch of a lyric line, as character offsets into its text, and the
/// time during which it lights up.
typedef LyricUnit = ({int start, int end, Duration from, Duration to});

/// How far along a line the fill is: everything before [sungEnd] is lit,
/// [current] is the stretch lighting up and [fraction] how much of it is.
typedef LyricFillState = ({int sungEnd, LyricUnit? current, double fraction});

/// The stretches of [line] that light up one after another.
///
/// When the file times each word, these are those words at those times.
///
/// Most files only say when a line starts. Then the line is divided into its
/// words and the time until [nextLineAt] is shared between them by length.
/// That is an even sweep, not knowledge of when each word is sung, and it is
/// capped so a line followed by a long instrumental gap doesn't crawl.
List<LyricUnit> lyricUnits(LyricLine line, {required Duration? nextLineAt}) {
  final text = line.text;
  final start = line.time;
  if (start == null || text.trim().isEmpty) return const [];

  final words = line.words;
  if (words.isNotEmpty) {
    final units = <LyricUnit>[];
    var cursor = 0;
    for (final (index, word) in words.indexed) {
      final piece = word.text.trim();
      final at = text.indexOf(piece, cursor);
      if (at < 0) continue;
      cursor = at + piece.length;
      final Duration to;
      if (index + 1 < words.length) {
        to = words[index + 1].time;
      } else {
        // The last word ends where the file says, else at the next line,
        // but is never held for longer than a long note.
        final limit = word.time + const Duration(milliseconds: 1500);
        final stated = line.end ?? nextLineAt;
        to = stated != null && stated > word.time && stated < limit
            ? stated
            : limit;
      }
      units.add((start: at, end: cursor, from: word.time, to: to));
    }
    return units;
  }

  // Words, or single characters for a script written without spaces.
  var pieces = [
    for (final match in RegExp(r'\S+').allMatches(text))
      (start: match.start, end: match.end),
  ];
  if (pieces.length == 1 && pieces.single.end - pieces.single.start > 8) {
    final only = pieces.single;
    var at = only.start;
    pieces = [
      for (final character in text.substring(only.start, only.end).characters)
        (start: at, end: at += character.length),
    ];
  }
  if (pieces.isEmpty) return const [];

  final letters = pieces.fold(0, (sum, piece) => sum + piece.end - piece.start);
  // Roughly how long this much text takes to sing, for when the next line is
  // a long way off.
  final estimate = Duration(
    milliseconds: math.max(2000, (320 * pieces.length + 55 * letters) * 3 ~/ 2),
  );
  final gap = nextLineAt == null ? null : nextLineAt - start;
  final window = gap == null || gap <= Duration.zero
      ? estimate
      : (gap * 0.96 < estimate ? gap * 0.96 : estimate);

  // Longer words get more of the time.
  final weights = [for (final piece in pieces) piece.end - piece.start + 1];
  final total = weights.fold(0, (sum, weight) => sum + weight);
  final units = <LyricUnit>[];
  var passed = 0;
  for (final (index, piece) in pieces.indexed) {
    final from = start + window * (passed / total);
    passed += weights[index];
    units.add((
      start: piece.start,
      end: piece.end,
      from: from,
      to: start + window * (passed / total),
    ));
  }
  return units;
}

/// Where the fill of [units] has got to at [position].
LyricFillState lyricFillAt(List<LyricUnit> units, Duration position) {
  var sungEnd = 0;
  for (final unit in units) {
    if (position >= unit.to) {
      sungEnd = unit.end;
      continue;
    }
    if (position < unit.from) break;
    final length = (unit.to - unit.from).inMicroseconds;
    return (
      sungEnd: sungEnd,
      current: unit,
      fraction: length <= 0
          ? 1
          : ((position - unit.from).inMicroseconds / length).clamp(0.0, 1.0),
    );
  }
  return (sungEnd: sungEnd, current: null, fraction: 0);
}

/// The lit part of a lyric line, drawn over the same text in its dim colour:
/// everything already sung, and the word being sung up to a soft edge that
/// moves across it. It repaints with [position], frame by frame.
///
/// It lays the text out exactly as the dim copy beneath it is laid out, so
/// the two coincide however the line wraps and whatever the script.
class LyricFill extends StatefulWidget {
  const LyricFill({
    super.key,
    required this.text,
    required this.style,
    required this.units,
    required this.position,
  });

  final String text;

  /// The lit style: the line's own style in its full colour.
  final TextStyle style;
  final List<LyricUnit> units;
  final ValueListenable<Duration> position;

  @override
  State<LyricFill> createState() => _LyricFillState();
}

class _LyricFillState extends State<LyricFill> {
  TextPainter? _painter;
  Object? _laidOutFor;

  TextPainter _layout(double maxWidth) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final key = (widget.text, widget.style, maxWidth, direction, scaler);
    final existing = _painter;
    if (existing != null && key == _laidOutFor) return existing;
    existing?.dispose();
    _laidOutFor = key;
    return _painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: maxWidth);
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final painter = _layout(box.maxWidth);
        return CustomPaint(
          size: painter.size,
          painter: _FillPainter(painter, widget.units, widget.position),
        );
      },
    );
  }
}

class _FillPainter extends CustomPainter {
  _FillPainter(this.text, this.units, this.position) : super(repaint: position);

  final TextPainter text;
  final List<LyricUnit> units;
  final ValueListenable<Duration> position;

  // Width of the soft edge of the fill, and room for the glow around glyphs.
  static const _feather = 12.0;
  static const _glow = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = lyricFillAt(units, position.value);

    if (fill.sungEnd > 0) {
      final sung = Path();
      for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: fill.sungEnd),
      )) {
        sung.addRect(_room(box.toRect()));
      }
      canvas
        ..save()
        ..clipPath(sung);
      text.paint(canvas, Offset.zero);
      canvas.restore();
    }

    final current = fill.current;
    if (current == null || fill.fraction <= 0) return;
    final boxes = text.getBoxesForSelection(
      TextSelection(baseOffset: current.start, extentOffset: current.end),
    );
    final width = boxes.fold(0.0, (sum, box) => sum + box.right - box.left);
    // The edge starts just before the word and ends just past it, so the
    // word is fully lit exactly when its time is up.
    var lit = fill.fraction * (width + _feather);
    for (final box in boxes) {
      final rect = box.toRect();
      final reach = math.min(lit, rect.width + _feather);
      lit -= rect.width;
      if (reach <= 0) break;
      final layer = _room(rect);
      final leftToRight = box.direction == TextDirection.ltr;
      // Fully lit up to `edge - feather`, fading out to nothing at `edge`.
      final edge = leftToRight ? rect.left + reach : rect.right - reach;
      final solid = leftToRight ? edge - _feather : edge + _feather;
      canvas.saveLayer(layer, Paint());
      text.paint(canvas, Offset.zero);
      canvas
        ..drawRect(
          layer,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader =
                LinearGradient(
                  begin: leftToRight
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  end: leftToRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  tileMode: TileMode.clamp,
                ).createShader(
                  leftToRight
                      ? Rect.fromLTRB(solid, layer.top, edge, layer.bottom)
                      : Rect.fromLTRB(edge, layer.top, solid, layer.bottom),
                ),
        )
        ..restore();
    }
  }

  Rect _room(Rect rect) => Rect.fromLTRB(
    rect.left,
    rect.top - _glow,
    rect.right,
    rect.bottom + _glow,
  );

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.text != text || old.units != units || old.position != position;
}
