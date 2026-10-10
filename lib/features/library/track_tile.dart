import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../data/models/track.dart';

/// One row in a track list.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onMenu,
    this.isCurrent = false,
  });

  final Track track;
  final VoidCallback onTap;

  /// Opens the track's actions. The menu button is hidden when null.
  final VoidCallback? onMenu;

  /// Whether this is the track loaded in the player right now.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, onMenu == null ? 20 : 4, 8),
        child: Row(
          children: [
            Artwork(path: track.artPath, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: isCurrent ? palette.accent : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${track.displayArtist} · ${track.displayAlbum}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatDuration(track.duration),
              style: text.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (onMenu != null)
              IconButton(
                tooltip: 'More for ${track.title}',
                onPressed: onMenu,
                icon: const Icon(Icons.more_vert_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
