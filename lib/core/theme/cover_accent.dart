import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import '../../app/providers.dart';

/// Accent colours taken from the current track's cover, one per brightness.
/// Both are null when there is no cover or it has no usable colour.
typedef CoverAccents = ({Color? light, Color? dark});

const CoverAccents _noCoverAccents = (light: null, dark: null);

/// Marks "the cover had no colourful region" when scoring its colours.
const _noSeed = 0;

/// Finds the most characterful colour in the image at [path], the same way
/// Material picks a seed colour from a wallpaper. Returns null for a missing
/// or undecodable file, and for covers that are essentially grey.
Future<Color?> seedColorFromCover(String path) async {
  final rgba = await _decodeSmall(path);
  if (rgba == null) return null;
  // Colour clustering is CPU work; keep it off the UI thread so a track
  // change never costs a frame.
  final seed = await Isolate.run(() => _seedFromRgba(rgba));
  return seed == _noSeed ? null : Color(seed);
}

/// Decodes the cover at a tiny size: plenty for picking a colour, and cheap.
Future<Uint8List?> _decodeSmall(String path) async {
  if (!File(path).existsSync()) return null;
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(targetWidth: 96);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData();
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return data?.buffer.asUint8List();
  } on Exception {
    return null;
  }
}

Future<int> _seedFromRgba(Uint8List rgba) async {
  final pixels = [
    for (var i = 0; i + 3 < rgba.length; i += 4)
      (rgba[i + 3] << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2],
  ];
  final quantized = await QuantizerCelebi().quantize(pixels, 64);
  return Score.score(
    quantized.colorToCount,
    desired: 1,
    fallbackColorARGB: _noSeed,
  ).first;
}

/// The most characterful colour of the cover at a path, for pages that take
/// their colour from a cover other than the playing track's.
final coverSeedProvider = FutureProvider.autoDispose.family<Color?, String>(
  (ref, path) => seedColorFromCover(path),
);

/// Adjusts a cover colour so it works as an accent: vivid enough to read as
/// one, and light or dark enough to stand out from the page behind it.
Color tuneAccent(Color seed, Brightness brightness) {
  final hsl = HSLColor.fromColor(seed);
  final lightness = brightness == Brightness.dark
      ? hsl.lightness.clamp(0.50, 0.66)
      : hsl.lightness.clamp(0.32, 0.46);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.45, 0.90))
      .withLightness(lightness)
      .toColor();
}

/// Black or white, whichever is readable on [accent].
Color onAccentFor(Color accent) =>
    ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
    ? Colors.white
    : const Color(0xFF0B0D12);

/// Cached cover image of the track loaded in the player, if it has one.
final currentArtPathProvider = Provider<String?>(
  (ref) => ref.watch(currentMediaItemProvider).value?.artUri?.toFilePath(),
);

/// Follows the current track and publishes accents from its cover. The
/// previous accent stays in place until the next one is ready, so the colour
/// moves straight from one cover's to the next without flashing in between.
class CoverAccentController extends Notifier<CoverAccents> {
  String? _wanted;

  @override
  CoverAccents build() {
    ref.listen(currentArtPathProvider, (_, path) => _resolve(path));
    final initial = ref.read(currentArtPathProvider);
    if (initial != null) _resolve(initial);
    return _noCoverAccents;
  }

  Future<void> _resolve(String? path) async {
    _wanted = path;
    final seed = path == null ? null : await seedColorFromCover(path);
    // A newer track may have taken over while this cover was being read.
    if (_wanted != path) return;
    state = seed == null
        ? _noCoverAccents
        : (
            light: tuneAccent(seed, Brightness.light),
            dark: tuneAccent(seed, Brightness.dark),
          );
  }
}

final coverAccentProvider =
    NotifierProvider<CoverAccentController, CoverAccents>(
      CoverAccentController.new,
    );
