import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../data/models/track.dart';

/// Lets the user tick tracks from the whole library, with a search to narrow
/// it down. Returns the ids they chose, in the order they ticked them, or
/// null if they backed out. Tracks in [alreadyIn] are shown as added and
/// cannot be ticked.
Future<List<int>?> showTrackPicker(
  BuildContext context, {
  required Set<int> alreadyIn,
}) => Navigator.of(context, rootNavigator: true).push<List<int>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TrackPicker(alreadyIn: alreadyIn),
  ),
);

class _TrackPicker extends ConsumerStatefulWidget {
  const _TrackPicker({required this.alreadyIn});

  final Set<int> alreadyIn;

  @override
  ConsumerState<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends ConsumerState<_TrackPicker> {
  // Kept in the order ticked, which is the order they will be added in.
  final _chosen = <int>{};
  String _query = '';

  bool _matches(Track track) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return track.title.toLowerCase().contains(query) ||
        track.displayArtist.toLowerCase().contains(query) ||
        track.displayAlbum.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final all = ref.watch(allTracksProvider);

    return NocBackdrop(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Add tracks',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge,
                      ),
                    ),
                    FilledButton(
                      onPressed: _chosen.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(_chosen.toList()),
                      child: Text(
                        _chosen.isEmpty ? 'Add' : 'Add ${_chosen.length}',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: palette.glass,
                    shape: StadiumBorder(
                      side: BorderSide(color: palette.glassBorder),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _query = value),
                            textInputAction: TextInputAction.search,
                            style: text.bodyMedium,
                            decoration: InputDecoration.collapsed(
                              hintText: 'Search tracks, artists, albums…',
                              hintStyle: text.bodyMedium?.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: all.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load your library",
                    message: '$error',
                  ),
                  data: (tracks) {
                    final shown = tracks.where(_matches).toList();
                    if (shown.isEmpty) {
                      return const EmptyState(
                        icon: Icons.music_off_outlined,
                        title: 'No matches',
                        message: 'Nothing in your library matches that.',
                      );
                    }
                    return ListView.builder(
                      itemCount: shown.length,
                      itemExtent: 64,
                      itemBuilder: (context, index) {
                        final track = shown[index];
                        final added = widget.alreadyIn.contains(track.id);
                        return _PickerRow(
                          track: track,
                          added: added,
                          chosen: _chosen.contains(track.id),
                          onTap: added
                              ? null
                              : () => setState(() {
                                  if (!_chosen.remove(track.id)) {
                                    _chosen.add(track.id);
                                  }
                                }),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.track,
    required this.added,
    required this.chosen,
    required this.onTap,
  });

  final Track track;

  /// Already in the collection, so it cannot be ticked.
  final bool added;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return Semantics(
      checked: chosen || added,
      enabled: !added,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: added ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Artwork(path: track.artPath, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
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
                if (added)
                  Text('Added', style: text.bodySmall)
                else
                  Icon(
                    chosen
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: chosen ? palette.accent : palette.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
