import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/theme/flex_type.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/features/lyrics/lyric_fill.dart';
import 'package:noctune/features/lyrics/lyrics.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void main() {
  group('a line the file times as a whole', () {
    const line = LyricLine('Hello brave world', Duration(seconds: 10));

    test('is split into its words, in order, covering the text', () {
      final units = lyricUnits(line, nextLineAt: const Duration(seconds: 12));

      expect(
        [for (final unit in units) line.text.substring(unit.start, unit.end)],
        ['Hello', 'brave', 'world'],
      );
    });

    test('shares the time until the next line between them', () {
      final units = lyricUnits(line, nextLineAt: const Duration(seconds: 12));

      expect(units.first.from, const Duration(seconds: 10));
      // Each word starts where the one before it ends.
      for (var i = 1; i < units.length; i++) {
        expect(units[i].from, units[i - 1].to);
      }
      // Finished just before the next line starts, never after it.
      expect(units.last.to, lessThanOrEqualTo(const Duration(seconds: 12)));
      expect(units.last.to, greaterThan(const Duration(seconds: 11)));
    });

    test('gives longer words more of the time', () {
      final units = lyricUnits(
        const LyricLine('a considerably longer', Duration.zero),
        nextLineAt: const Duration(seconds: 3),
      );

      Duration length(LyricUnit unit) => unit.to - unit.from;
      expect(length(units[1]), greaterThan(length(units[0])));
    });

    test('does not crawl through a long gap before the next line', () {
      final units = lyricUnits(line, nextLineAt: const Duration(seconds: 40));

      expect(units.last.to, lessThan(const Duration(seconds: 15)));
    });

    test('still fills when it is the last line of the song', () {
      final units = lyricUnits(line, nextLineAt: null);

      expect(units, hasLength(3));
      expect(units.last.to, greaterThan(line.time!));
    });

    test('text written without spaces fills character by character', () {
      const unspaced = LyricLine('一二三四五六七八九十', Duration.zero);

      expect(
        lyricUnits(unspaced, nextLineAt: const Duration(seconds: 4)),
        hasLength(10),
      );
    });

    test('a gap or an untimed line has nothing to fill', () {
      expect(
        lyricUnits(const LyricLine('', Duration.zero), nextLineAt: null),
        isEmpty,
      );
      expect(lyricUnits(const LyricLine('Words'), nextLineAt: null), isEmpty);
    });
  });

  group('a line whose words the file times', () {
    final line = parseLyrics(
      '[00:10.00]<00:10.00>One <00:10.40>two <00:11.30>three<00:11.90>\n'
      '[00:20.00]Next',
    )!.lines.first;

    test('uses exactly those times', () {
      final units = lyricUnits(line, nextLineAt: const Duration(seconds: 20));

      expect(
        [for (final unit in units) line.text.substring(unit.start, unit.end)],
        ['One', 'two', 'three'],
      );
      expect(
        [for (final unit in units) unit.from],
        [_ms(10000), _ms(10400), _ms(11300)],
      );
      // The last word ends at the closing stamp, not at the next line.
      expect(units.last.to, _ms(11900));
    });

    test('never holds the last word for longer than a long note', () {
      final open = parseLyrics(
        '[00:10.00]<00:10.00>One <00:10.40>two\n[01:00.00]Next',
      )!.lines.first;

      final units = lyricUnits(open, nextLineAt: const Duration(minutes: 1));

      expect(units.last.to, _ms(10400 + 1500));
    });
  });

  group('how far the fill has got', () {
    final units = <LyricUnit>[
      (start: 0, end: 5, from: _ms(1000), to: _ms(2000)),
      (start: 6, end: 11, from: _ms(2000), to: _ms(4000)),
    ];

    test('nothing is lit before the line starts', () {
      final fill = lyricFillAt(units, _ms(500));

      expect(fill.sungEnd, 0);
      expect(fill.current, isNull);
    });

    test('the word being sung is lit in proportion to its time', () {
      final fill = lyricFillAt(units, _ms(1250));

      expect(fill.sungEnd, 0);
      expect(fill.current, units.first);
      expect(fill.fraction, closeTo(0.25, 1e-9));
    });

    test('finished words stay lit while the next one fills', () {
      final fill = lyricFillAt(units, _ms(3000));

      expect(fill.sungEnd, 5);
      expect(fill.current, units.last);
      expect(fill.fraction, closeTo(0.5, 1e-9));
    });

    test('the whole line is lit once it has been sung', () {
      final fill = lyricFillAt(units, _ms(9000));

      expect(fill.sungEnd, 11);
      expect(fill.current, isNull);
    });
  });

  group('the lit copy of a line', () {
    const text = "I'm on the bridge with a tank of unleaded";
    const all = TextSelection(baseOffset: 0, extentOffset: text.length);

    // Where every letter of the dim copy, a Text, is drawn.
    List<TextBox> dim(WidgetTester tester) => tester
        .renderObject<RenderParagraph>(find.text(text))
        .getBoxesForSelection(all);

    // And where the lit copy over it draws them.
    List<TextBox> lit(WidgetTester tester, TextStyle style) {
      final painter = LyricFill.layOut(
        tester.element(find.byType(LyricFill)),
        text: text,
        style: style,
        maxWidth: 330,
      );
      addTearDown(painter.dispose);
      return painter.getBoxesForSelection(all);
    }

    // The two copies as the lyrics draw them: the dim one in grey, the lit
    // one over it in white with a glow.
    TextStyle lighted(TextStyle style) => style.copyWith(
      color: const Color(0xFFFFFFFF),
      shadows: const [Shadow(color: Color(0x80FFFFFF), blurRadius: 8)],
    );
    Widget copies(TextStyle style) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 330,
        child: Stack(
          children: [
            Text(text, style: style.copyWith(color: const Color(0x6BFFFFFF))),
            LyricFill(
              text: text,
              style: lighted(style),
              units: const [],
              position: ValueNotifier(Duration.zero),
            ),
          ],
        ),
      ),
    );

    testWidgets('lands on the dim copy under it, letter for letter', (
      tester,
    ) async {
      // As in the app: its typeface, its theme and its language. A Text is
      // laid out for the app's language, which moves these letters by a
      // pixel; laid out without it, the lit copy sits that much lower.
      await tester.runAsync(
        () =>
            (FontLoader(FlexType.family)..addFont(
                  File('assets/fonts/GoogleSansFlex.ttf')
                      .readAsBytes()
                      .then(ByteData.sublistView),
                ))
                .load(),
      );
      final style = FlexType.custom(
        size: 30,
        lineHeight: 30 * 1.38,
        weight: 700,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildNocTheme(Brightness.dark, NocAccent.red),
          home: Material(child: copies(style)),
        ),
      );

      // The text engine keeps layouts it has made and can hand one back for
      // the same words later, so a layout made without the app's language
      // may come out right or wrong depending on what came before it. Make
      // one the way the lit copy used to, so this does not pass by luck.
      TextPainter(
          text: TextSpan(text: text, style: lighted(style)),
          textDirection: TextDirection.ltr,
        )
        ..layout(maxWidth: 330)
        ..dispose();

      expect(dim(tester).length, greaterThan(1));
      expect(lit(tester, lighted(style)), dim(tester));
      expect(
        tester.getSize(find.byType(LyricFill)),
        tester.getSize(find.text(text)),
      );
    });

    testWidgets('follows the page when its text style changes', (tester) async {
      // A style that leaves its tracking to the page around it.
      const style = TextStyle(fontSize: 30, height: 1.4);
      Future<void> pump(double tracking) => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: TextStyle(fontSize: 14, letterSpacing: tracking),
            child: copies(style),
          ),
        ),
      );

      await pump(0);
      final before = dim(tester);
      await pump(0.5);

      expect(dim(tester), isNot(before));
      expect(lit(tester, lighted(style)), dim(tester));
      expect(
        tester.getSize(find.byType(LyricFill)),
        tester.getSize(find.text(text)),
      );
    });
  });
}
