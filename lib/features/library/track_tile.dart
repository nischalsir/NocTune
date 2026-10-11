import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/glass_circle.dart';
import '../../data/models/track.dart';

/// One row in a track list.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.onMenu,
    this.isCurrent = false,
    this.playButton = false,
  });

  final Track track;
  final VoidCallback onTap;

  /// Opens the track's actions, from the menu button or by pressing and
  /// holding the row. There is neither when null.
  final VoidCallback? onMenu;

  /// End the row with a round play button in place of the menu button. The
  /// menu is then reached by pressing and holding only.
  final bool playButton;

  /// Whether this is the track loaded in the player right now.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final menuButton = onMenu != null && !playButton;
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, menuButton ? 4 : 16, 8),
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
            if (playButton) ...[
              const SizedBox(width: 12),
              // The row plays on a tap as well, so to assistive technology
              // this is one control, not two.
              ExcludeSemantics(
                child: GestureDetector(
                  onTap: onTap,
                  child: const GlassCircle(Icons.play_arrow_rounded, size: 38),
                ),
              ),
            ],
            if (menuButton)
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
