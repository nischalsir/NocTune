import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/track.dart';
import 'track_menu.dart';
import 'track_tile.dart';

/// A scrolling list of tracks loaded from a provider, with loading, error
/// and empty states. Tapping a track plays the whole list from that track.
class TrackListView extends ConsumerWidget {
  const TrackListView({super.key, required this.tracks, required this.empty});

  final AsyncValue<List<Track>> tracks;

  /// Shown when the list has loaded and contains nothing.
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentTrackIdProvider);
    return tracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load these tracks",
        message: '$error',
      ),
      data: (tracks) {
        if (tracks.isEmpty) return empty;
        return ListView.builder(
          itemCount: tracks.length,
          itemExtent: 64,
          itemBuilder: (context, index) {
            final track = tracks[index];
            return TrackTile(
              track: track,
              isCurrent: track.id == currentId,
              onTap: () => ref
                  .read(audioHandlerProvider)
                  .playTracks(tracks, initialIndex: index),
              onMenu: () => showTrackMenu(context, ref, track),
            );
          },
        );
      },
    );
  }
}
