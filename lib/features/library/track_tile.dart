import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/glass_circle.dart';
import '../../core/widgets/play_pause_icon.dart';
import '../../core/widgets/press_scale.dart';
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
    this.playing = false,
    this.onPlayPause,
    this.action,
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

  /// Whether the player is playing right now.
  final bool playing;

  /// Pauses the player, or carries on from where it paused. When given, the
  /// round button on the current track's row does this, and shows which,
  /// in place of starting the track again.
  final VoidCallback? onPlayPause;

  /// Ends the row in place of the menu button, such as a download button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final action = this.action;
    final menuButton = onMenu != null && !playButton && action == null;
    final pauses = isCurrent && onPlayPause != null;
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          menuButton || action != null ? 4 : 16,
          8,
        ),
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
              if (pauses)
                // Unlike the row, which starts the track again.
                Semantics(
                  container: true,
                  button: true,
                  label: playing ? 'Pause' : 'Play',
                  child: GestureDetector(
                    onTap: onPlayPause,
                    child: PressScale(
                      child: GlassCircle.glyph(
                        PlayPauseIcon(
                          playing: playing,
                          size: 18,
                          color: palette.textPrimary,
                        ),
                        size: 38,
                      ),
                    ),
                  ),
                )
              else
                // The row plays on a tap as well, so to assistive technology
                // this is one control, not two.
                ExcludeSemantics(
                  child: GestureDetector(
                    onTap: onTap,
                    child: const PressScale(
                      child: GlassCircle(Icons.play_arrow_rounded, size: 38),
                    ),
                  ),
                ),
            ],
            ?action,
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
