import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/models/track.dart';
import 'download_action.dart';
import 'external_search.dart';
import 'musicbrainz_source.dart';
import 'online_search.dart';

/// A release found on MusicBrainz: its cover, name and date, buttons to
/// open it in Spotify or YouTube Music, and its songs. A song already in
/// the library plays from there; any other opens elsewhere.
class ReleaseScreen extends ConsumerWidget {
  const ReleaseScreen({super.key, required this.release});

  final Release release;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(releaseTracksProvider(release));
    final library = ref.watch(allTracksProvider).value ?? const <Track>[];
    final currentId = ref.watch(currentTrackIdProvider);
    final text = Theme.of(context).textTheme;

    final songs = tracks.value ?? const <ReleaseTrack>[];
    final owned = [
      for (final song in songs) libraryMatch(library, song.title, song.artist),
    ];
    final playable = owned.nonNulls.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: NocBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Artwork(
                      path: null,
                      url: release.coverUrl,
                      size: 180,
                      radius: 16,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      release.title,
                      textAlign: TextAlign.center,
                      style: text.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      release.artist,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${release.type} · ${release.date}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _OpenElsewhere(
                  words: '${release.artist} ${release.title}',
                ),
              ),
              if (playable.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: PillButton(
                    filled: true,
                    icon: Icons.play_arrow_rounded,
                    label: playable.length == 1
                        ? 'Play the 1 song you have'
                        : 'Play the ${playable.length} songs you have',
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTracks(playable, initialIndex: 0),
                  ),
                ),
              switch (tracks) {
                AsyncData() when songs.isEmpty => const _Message(
                  'MusicBrainz has no track list for this yet.',
                ),
                AsyncData() => Column(
                  children: [
                    for (final (index, song) in songs.indexed)
                      _SongRow(
                        number: index + 1,
                        song: song,
                        release: release,
                        owned: owned[index],
                        isCurrent:
                            owned[index] != null &&
                            owned[index]!.id == currentId,
                        onPlay: () => ref
                            .read(audioHandlerProvider)
                            .playTracks(
                              playable,
                              initialIndex: playable.indexOf(owned[index]!),
                            ),
                      ),
                  ],
                ),
                AsyncError() => Column(
                  children: [
                    const _Message(
                      "MusicBrainz couldn't be reached right now.",
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 0, 48, 0),
                      child: PillButton(
                        icon: Icons.refresh_rounded,
                        label: 'Try again',
                        onTap: () =>
                            ref.invalidate(releaseTracksProvider(release)),
                      ),
                    ),
                  ],
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// One song of the release: plays when it is in the library, otherwise
/// offers to open it elsewhere.
class _SongRow extends ConsumerWidget {
  const _SongRow({
    required this.number,
    required this.song,
    required this.release,
    required this.owned,
    required this.isCurrent,
    required this.onPlay,
  });

  final int number;
  final ReleaseTrack song;
  final Release release;
  final Track? owned;
  final bool isCurrent;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.noc;
    final details = [
      if (song.artist != release.artist) song.artist,
      if (owned != null) 'In your library',
      if (song.length > Duration.zero) formatDuration(song.length),
    ].join(' · ');
    return InkWell(
      onTap: owned != null
          ? onPlay
          : () => showOpenElsewhereSheet(
              context,
              title: song.title,
              subtitle: song.artist,
              words: '${song.artist} ${song.title}',
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$number',
                style: text.bodySmall?.copyWith(color: palette.textTertiary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                owned != null
                    ? Icons.play_arrow_rounded
                    : Icons.open_in_new_rounded,
                color: owned != null ? null : palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Open in Spotify and Open in YouTube Music, side by side.
class _OpenElsewhere extends ConsumerWidget {
  const _OpenElsewhere({required this.words});

  final String words;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      Expanded(
        child: PillButton(
          label: 'Spotify',
          icon: Icons.open_in_new_rounded,
          onTap: () => _open(context, ref, searchOnSpotify, 'Spotify', words),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: PillButton(
          label: 'YouTube Music',
          icon: Icons.open_in_new_rounded,
          onTap: () =>
              _open(context, ref, searchOnYouTubeMusic, 'YouTube Music', words),
        ),
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

/// Opens the page for [release].
void openRelease(BuildContext context, Release release) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ReleaseScreen(release: release)),
  );
}

/// Offers to open [words] in Spotify or YouTube Music.
Future<void> showOpenElsewhereSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String words,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  backgroundColor: context.noc.glassSolid,
  builder: (sheetContext) => Consumer(
    builder: (sheetContext, ref, _) {
      void open(
        Future<bool> Function(LinkOpener open, String words) search,
        String name,
      ) {
        Navigator.of(sheetContext).pop();
        _open(context, ref, search, name, words);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open in Spotify'),
              onTap: () => open(searchOnSpotify, 'Spotify'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open in YouTube Music'),
              onTap: () => open(searchOnYouTubeMusic, 'YouTube Music'),
            ),
          ],
        ),
      );
    },
  ),
);

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  Future<bool> Function(LinkOpener open, String words) search,
  String name,
  String words,
) async {
  final opened = await search(ref.read(linkOpenerProvider), words);
  if (!opened && context.mounted) say(context, "Couldn't open $name.");
}

/// The library's copy of the song [title] by [artist], or null. Titles are
/// compared without capitals, punctuation or bracketed parts such as
/// "(feat. …)", and the artists must share a name.
Track? libraryMatch(List<Track> library, String title, String artist) {
  final wanted = _plain(title);
  if (wanted.isEmpty) return null;
  final names = _names(artist);
  for (final track in library) {
    if (_plain(track.title) != wanted) continue;
    final theirs = _names(track.artist ?? '');
    if (theirs.any(names.contains)) return track;
  }
  return null;
}

String _plain(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[(\[][^)\]]*[)\]]'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// The separate names in an artist credit such as "A feat. B & C".
Set<String> _names(String credit) => {
  for (final name in credit.toLowerCase().split(
    RegExp(r'\s*(?:,|&|;|/|\bfeat\.?|\bft\.?|\bx\b|\band\b|\bwith\b)\s*'),
  ))
    if (_plain(name) case final plain when plain.isNotEmpty) plain,
};
