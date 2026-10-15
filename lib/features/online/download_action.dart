import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import 'online_playback.dart';
import 'online_source.dart';

/// Shows [message] in a snackbar, in place of any showing.
void say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The end of an online result's row: a download button, or how it stands.
class DownloadAction extends ConsumerWidget {
  const DownloadAction({
    super.key,
    required this.track,
    required this.downloaded,
    required this.offline,
    required this.status,
  });

  final OnlineTrack track;
  final bool downloaded;
  final bool offline;
  final DownloadStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.noc;
    if (downloaded) {
      return _Mark(
        Icons.download_done_rounded,
        'Downloaded',
        color: palette.accent,
      );
    }
    if (offline) {
      return _Mark(
        Icons.cloud_off_rounded,
        'Needs an internet connection',
        color: palette.textTertiary,
      );
    }
    if (status == DownloadStatus.downloading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (track.downloadUrl == null) return const SizedBox(width: 12);
    final failed = status == DownloadStatus.failed;
    return IconButton(
      tooltip: failed
          ? "Couldn't download ${track.title}. Try again"
          : 'Download ${track.title}',
      onPressed: () async {
        final saved = await ref
            .read(onlineDownloadsProvider.notifier)
            .download(track);
        if (!saved && context.mounted) {
          say(
            context,
            "${track.title} couldn't be downloaded. Check the connection "
            'and try again.',
          );
        }
      },
      icon: Icon(
        failed ? Icons.refresh_rounded : Icons.download_rounded,
        color: failed ? palette.textSecondary : null,
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.icon, this.label, {required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, color: color, semanticLabel: label),
    ),
  );
}
