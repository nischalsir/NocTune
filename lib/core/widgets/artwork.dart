import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';

/// Square album artwork loaded from the on-device cache, with a neutral
/// placeholder when a track has none or the file can't be decoded.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.path,
    required this.size,
    this.radius = 10,
  });

  /// Cached artwork file, or null when the track has no artwork.
  final String? path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final placeholder = _Placeholder(size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decode at display size so a 3000px cover doesn't sit in memory.
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return ColoredBox(
      color: palette.glassSolid,
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.45,
        color: palette.textTertiary,
      ),
    );
  }
}
