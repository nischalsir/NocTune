// Draws the NocTune app icon and writes every size Android and iOS need.
//
// Run from the project root with:
//
//     flutter test tool/generate_app_icon.dart
//
// (It runs under `flutter test` because drawing needs the Flutter engine.)
// Each size is drawn from the vector shapes below, not scaled from one bitmap.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _moon = Color(0xFFE9ECF2);
const _bars = Color(0xFFE5182B);
const _backgroundTop = Color(0xFF171B2B);
const _backgroundBottom = Color(0xFF05060A);

/// Paints the glyph: a crescent moon cradling three sound bars. It is drawn
/// in a 100×100 box centred in the canvas and occupying [scale] of its width.
void _paintGlyph(
  Canvas canvas,
  double size, {
  required double scale,
  required Color moon,
  required Color bars,
}) {
  final unit = size * scale / 100;
  canvas
    ..save()
    ..translate((size - 100 * unit) / 2, (size - 100 * unit) / 2)
    ..scale(unit);

  final crescent = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: const Offset(46, 51), radius: 36)),
    Path()..addOval(Rect.fromCircle(center: const Offset(60, 42), radius: 31)),
  );
  canvas.drawPath(crescent, Paint()..color = moon);

  final barPaint = Paint()..color = bars;
  for (final (x, top, bottom) in [
    (54.0, 36.0, 58.0),
    (65.0, 26.0, 64.0),
    (76.0, 38.0, 56.0),
  ]) {
    canvas.drawRRect(
      RRect.fromLTRBR(
        x - 3.6,
        top,
        x + 3.6,
        bottom,
        const Radius.circular(3.6),
      ),
      barPaint,
    );
  }
  canvas.restore();
}

/// Paints the midnight background with a faint red glow in one corner.
void _paintBackground(Canvas canvas, double size) {
  final bounds = Offset.zero & Size.square(size);
  canvas
    ..drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_backgroundTop, _backgroundBottom],
        ).createShader(bounds),
    )
    ..drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, 0.9),
          radius: 0.9,
          colors: [_bars.withValues(alpha: 0.34), _bars.withValues(alpha: 0)],
        ).createShader(bounds),
    );
}

Future<Uint8List> _render(
  int pixels,
  void Function(Canvas canvas, double size) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), pixels.toDouble());
  final image = await recorder.endRecording().toImage(pixels, pixels);
  final rgba = await image.toByteData();
  image.dispose();
  return rgba!.buffer.asUint8List();
}

// ---- PNG encoding ----
//
// Written out by hand so iOS icons can be saved without an alpha channel,
// which the App Store requires and the engine's own encoder can't produce.

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c.isOdd ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  var crc = 0xFFFFFFFF;
  for (final byte in body) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  crc ^= 0xFFFFFFFF;
  List<int> u32(int v) => [
    v >> 24 & 0xFF,
    v >> 16 & 0xFF,
    v >> 8 & 0xFF,
    v & 0xFF,
  ];
  return [...u32(data.length), ...body, ...u32(crc)];
}

Uint8List _encodePng(Uint8List rgba, int pixels, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final rows = BytesBuilder();
  for (var y = 0; y < pixels; y++) {
    rows.addByte(0); // no row filter
    for (var x = 0; x < pixels; x++) {
      final i = (y * pixels + x) * 4;
      rows.add(Uint8List.sublistView(rgba, i, i + channels));
    }
  }
  List<int> u32(int v) => [
    v >> 24 & 0xFF,
    v >> 16 & 0xFF,
    v >> 8 & 0xFF,
    v & 0xFF,
  ];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    ..._chunk('IHDR', [
      ...u32(pixels),
      ...u32(pixels),
      8,
      alpha ? 6 : 2,
      0,
      0,
      0,
    ]),
    ..._chunk('IDAT', ZLibEncoder(level: 9).convert(rows.takeBytes())),
    ..._chunk('IEND', const []),
  ]);
}

Future<void> _write(
  String path,
  int pixels,
  void Function(Canvas canvas, double size) paint, {
  bool alpha = true,
}) async {
  final png = _encodePng(await _render(pixels, paint), pixels, alpha: alpha);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png);
}

void main() {
  testWidgets('generate app icons', (tester) async {
    await tester.runAsync(() async {
      // Opaque square: iOS, and the image shown in the README.
      void full(Canvas canvas, double size) {
        _paintBackground(canvas, size);
        _paintGlyph(canvas, size, scale: 0.66, moon: _moon, bars: _bars);
      }

      // Rounded square on transparency, for Android launchers older than 8.
      void legacy(Canvas canvas, double size) {
        canvas.clipRRect(
          RRect.fromRectAndRadius(
            Offset.zero & Size.square(size),
            Radius.circular(size * 0.22),
          ),
        );
        full(canvas, size);
      }

      // Adaptive icon layers: the launcher masks and may crop them, so the
      // glyph stays inside the guaranteed-visible centre.
      void foreground(Canvas canvas, double size) =>
          _paintGlyph(canvas, size, scale: 0.46, moon: _moon, bars: _bars);
      void monochrome(Canvas canvas, double size) => _paintGlyph(
        canvas,
        size,
        scale: 0.46,
        moon: Colors.white,
        bars: Colors.white,
      );

      const res = 'android/app/src/main/res';
      for (final (density, factor) in [
        ('mdpi', 1.0),
        ('hdpi', 1.5),
        ('xhdpi', 2.0),
        ('xxhdpi', 3.0),
        ('xxxhdpi', 4.0),
      ]) {
        final dir = '$res/mipmap-$density';
        await _write('$dir/ic_launcher.png', (48 * factor).round(), legacy);
        await _write(
          '$dir/ic_launcher_foreground.png',
          (108 * factor).round(),
          foreground,
        );
        await _write(
          '$dir/ic_launcher_monochrome.png',
          (108 * factor).round(),
          monochrome,
        );
        await _write(
          '$dir/ic_launcher_background.png',
          (108 * factor).round(),
          _paintBackground,
          alpha: false,
        );
      }

      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      for (final (name, pixels) in [
        ('20x20@1x', 20),
        ('20x20@2x', 40),
        ('20x20@3x', 60),
        ('29x29@1x', 29),
        ('29x29@2x', 58),
        ('29x29@3x', 87),
        ('40x40@1x', 40),
        ('40x40@2x', 80),
        ('40x40@3x', 120),
        ('60x60@2x', 120),
        ('60x60@3x', 180),
        ('76x76@1x', 76),
        ('76x76@2x', 152),
        ('83.5x83.5@2x', 167),
        ('1024x1024@1x', 1024),
      ]) {
        await _write('$ios/Icon-App-$name.png', pixels, full, alpha: false);
      }

      await _write('docs/icon.png', 512, legacy);
    });
  });
}
