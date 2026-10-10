import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/theme/cover_accent.dart';

/// Writes a flat-colour PNG "cover" and returns its path.
Future<String> _cover(Directory dir, String name, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = color);
  final image = await recorder.endRecording().toImage(64, 64);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name.png')
    ..writeAsBytesSync(png!.buffer.asUint8List());
  return file.path;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('noctune_cover'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('seedColorFromCover', () {
    testWidgets('takes its colour from the cover', (tester) async {
      await tester.runAsync(() async {
        final blue = await seedColorFromCover(
          await _cover(temp, 'blue', const Color(0xFF1E5BD8)),
        );
        final orange = await seedColorFromCover(
          await _cover(temp, 'orange', const Color(0xFFE8731A)),
        );

        expect(HSLColor.fromColor(blue!).hue, closeTo(220, 20));
        expect(HSLColor.fromColor(orange!).hue, closeTo(26, 20));
      });
    });

    testWidgets('finds no accent in a grey cover', (tester) async {
      await tester.runAsync(() async {
        final grey = await seedColorFromCover(
          await _cover(temp, 'grey', const Color(0xFF808080)),
        );

        expect(grey, isNull);
      });
    });

    testWidgets('copes with a missing or unreadable file', (tester) async {
      await tester.runAsync(() async {
        final junk = File('${temp.path}/junk.jpg')..writeAsBytesSync([1, 2, 3]);

        expect(await seedColorFromCover('${temp.path}/nope.jpg'), isNull);
        expect(await seedColorFromCover(junk.path), isNull);
      });
    });
  });

  group('tuneAccent', () {
    test('keeps the hue while making the colour usable as an accent', () {
      const murky = Color(0xFF2A1A12);

      final onDark = tuneAccent(murky, Brightness.dark);
      final onLight = tuneAccent(murky, Brightness.light);

      expect(
        HSLColor.fromColor(onDark).hue,
        closeTo(HSLColor.fromColor(murky).hue, 2),
      );
      expect(HSLColor.fromColor(onDark).lightness, greaterThanOrEqualTo(0.5));
      expect(HSLColor.fromColor(onDark).saturation, greaterThanOrEqualTo(0.45));
      expect(HSLColor.fromColor(onLight).lightness, lessThanOrEqualTo(0.46));
    });

    test('pales a blinding colour for dark surfaces', () {
      final tuned = tuneAccent(const Color(0xFFFFFDE0), Brightness.dark);

      expect(HSLColor.fromColor(tuned).lightness, lessThanOrEqualTo(0.66));
    });
  });

  test('onAccentFor picks readable text', () {
    expect(onAccentFor(const Color(0xFF7A1020)), Colors.white);
    expect(onAccentFor(const Color(0xFFFFE066)), const Color(0xFF0B0D12));
  });
}
