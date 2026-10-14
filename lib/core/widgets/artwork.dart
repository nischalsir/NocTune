import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/noc_palette.dart';

/// Square album artwork loaded from the on-device cache, or from the web
/// for a streamed track, with a neutral placeholder when a track has none or
/// the image can't be loaded.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.path,
    required this.size,
    this.radius = 10,
    this.url,
  });

  /// Cached artwork file, or null when the track has no artwork.
  final String? path;

  /// Used when there is no [path].
  final Uri? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final url = this.url;
    final placeholder = _Placeholder(size: size);
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decode at display size so a 3000px cover doesn't sit in memory.
                cacheWidth: cacheWidth,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              )
            : url != null
            ? Image.network(
                '$url',
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                // Offline, or the image has gone: the placeholder.
                errorBuilder: (_, _, _) => placeholder,
              )
            : placeholder,
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
