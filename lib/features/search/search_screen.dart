import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/models/track.dart';
import '../library/track_menu.dart';
import '../library/track_tile.dart';
import '../online/download_action.dart';
import '../online/external_search.dart';
import '../online/musicbrainz_source.dart';
import '../online/online_album_screen.dart';
import '../online/online_playback.dart';
import '../online/online_search.dart';
import '../online/online_source.dart';
import '../online/release_screen.dart';
import 'search_history.dart';

/// Searches the library by title, artist, album and file name as you type,
/// and free music online: Jamendo (when the build has a client id), Audius
/// and the Internet Archive, each unless switched off. When the words name an
/// artist, their newest releases from MusicBrainz, each opening to its
/// songs. Buttons open the same search in those apps. With nothing typed it lists the
/// searches made lately, to run again.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  final _focus = FocusNode();
  bool _wasShowing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page stays alive while another tab is showing, with its tickers
    // paused. When it comes to the front, put the cursor in the field so the
    // keyboard opens straight away.
    final showing = TickerMode.valuesOf(context).enabled;
    if (showing && !_wasShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _wasShowing = showing;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A search counts as made once it is sent from the keyboard or one of its
  /// results is played, not on every letter typed.
  void _remember() => ref.read(searchHistoryProvider.notifier).add(_query);

  void _searchAgain(String search) {
    _field.value = TextEditingValue(
      text: search,
      selection: TextSelection.collapsed(offset: search.length),
    );
    setState(() => _query = search);
    _remember();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final history = ref.watch(searchHistoryProvider);
    final online = ref.watch(onlineSourcesProvider).isNotEmpty;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _field,
              focusNode: _focus,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) => _remember(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tracks, artists, albums…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: palette.glass,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: palette.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: palette.glassBorder),
                ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isNotEmpty
                ? _Results(query: _query.trim(), onPlayed: _remember)
                : history.isEmpty
                ? EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search your library',
                    message: online
                        ? 'Find a track by its title, artist, album or '
                              'file name, and free music online.'
                        : 'Find a track by its title, artist, album or '
                              'file name.',
                  )
                : _RecentSearches(
                    searches: history,
                    onSearch: _searchAgain,
                    onClear: ref.read(searchHistoryProvider.notifier).clear,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The library's matches, then one list from every online source, mixed in
/// turn. Each part loads and fails on its own, so a slow or failing source
/// never holds back the library or the other sources.
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onPlayed});

  final String query;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(searchResultsProvider(query));
    final latest = ref.watch(latestReleasesProvider(query));
    final (artist, releases) = latest.value ?? ('', const <Release>[]);
    final sources = ref.watch(onlineSourcesProvider);
    final answers = [
      for (final source in sources)
        (source.id, ref.watch(onlineSourceSearchProvider((source.id, query)))),
    ];
    final currentId = ref.watch(currentTrackIdProvider);
    final currentUri = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    // Rebuilds the rows as downloads start, finish or fail.
    final downloads = ref.watch(onlineDownloadsProvider);
    final paths = ref.watch(appPathsProvider);

    final localTracks = local.value ?? const <Track>[];
    final results = [
      for (final (id, answer) in answers)
        if (answer.value case final results?)
          (id, results)
        // Never expected: the search catches its failures. Shown as one.
        else if (answer.hasError)
          (id, const OnlineResults([], failure: OnlineFailure.unavailable)),
    ];
    final items = interleave([
      for (final (_, results) in results) results.items,
    ]);
    final songs = items.whereType<OnlineTrack>().toList();
    final loading = answers.any((answer) => answer.$2.isLoading);
    final failed = results.any((answer) => answer.$2.failure != null);
    // The sources that couldn't be reached. Only when none could is the
    // phone taken to be offline; otherwise one source is blocked or slow,
    // and the others play as usual.
    final offline = {
      for (final (id, results) in results)
        if (results.failure == OnlineFailure.offline) id,
    };
    final allOffline = offline.isNotEmpty && offline.length == results.length;
    final notes = [
      if (allOffline)
        results.any((answer) => answer.$2.fromCache)
            ? "You're offline. These are from an earlier search; only "
                  'downloaded songs can play.'
            : "You're offline. Online results appear once you're connected; "
                  'songs you downloaded are in your library.',
      for (final (id, results) in results)
        switch (results.failure) {
          OnlineFailure.rateLimited =>
            '${id.label} is busy right now. Try again in a minute.',
          OnlineFailure.offline when !allOffline =>
            "${id.label} couldn't be reached right now.",
          OnlineFailure.unavailable =>
            "${id.label} couldn't be reached right now.",
          _ => null,
        },
    ].nonNulls;

    if (local.hasValue &&
        localTracks.isEmpty &&
        !loading &&
        items.isEmpty &&
        !failed &&
        !latest.isLoading &&
        releases.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.music_off_outlined,
              title: 'No matches',
              message: sources.isNotEmpty
                  ? 'Nothing in your library or online matches "$query".'
                  : 'Nothing in your library matches "$query".',
            ),
          ),
          _ElsewhereButtons(query: query),
        ],
      );
    }

    Future<void> playOnline(BuildContext context, OnlineTrack track) async {
      final outcome = await ref
          .read(onlinePlayerProvider)
          .play(songs, songs.indexOf(track), offline: offline);
      if (!context.mounted) return;
      if (outcome == OnlinePlayOutcome.started) {
        onPlayed();
        return;
      }
      say(
        context,
        '${track.title} needs an internet connection. '
        'Download it while online to play it offline.',
      );
    }

    Widget songRow(BuildContext context, OnlineTrack track) {
      final file = downloadedFile(paths, track);
      final downloaded = file.existsSync();
      final copy = Uri.file(file.path).toString();
      final unreachable = offline.contains(track.source);
      return Opacity(
        // Can't play right now: no connection and no copy on the device.
        opacity: unreachable && !downloaded ? 0.5 : 1,
        child: TrackTile(
          track: streamedTrack(track),
          isCurrent:
              currentUri == '${track.streamUrl}' ||
              (downloaded && currentUri == copy),
          playing: playing,
          onTap: () => playOnline(context, track),
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              _Badge(track.source),
              DownloadAction(
                track: track,
                downloaded: downloaded,
                offline: unreachable,
                status: downloads[track.key],
              ),
            ],
          ),
        ),
      );
    }

    final rows = <WidgetBuilder>[
      if (!local.hasValue) (_) => const _Progress('Searching your library…'),
      if (localTracks.isNotEmpty) (_) => const _Heading('In your library'),
      for (final (index, track) in localTracks.indexed)
        (context) => TrackTile(
          track: track,
          isCurrent: track.id == currentId,
          playing: playing,
          onTap: () {
            ref
                .read(audioHandlerProvider)
                .playTracks(localTracks, initialIndex: index);
            onPlayed();
          },
          onMenu: () => showTrackMenu(context, ref, track),
        ),
      if (releases.isNotEmpty) (_) => _Heading('Latest from $artist'),
      for (final release in releases) (_) => _ReleaseRow(release: release),
      if (sources.isNotEmpty) (_) => const _Heading('Online'),
      for (final note in notes) (_) => _Note(note),
      for (final item in items)
        switch (item) {
          final OnlineTrack track => (context) => songRow(context, track),
          final OnlineAlbum album => (context) => _AlbumRow(album: album),
        },
      if (loading) (_) => const _Progress('Searching…'),
      (_) => _ElsewhereButtons(query: query),
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
    );
  }
}

/// An album or show found online; opens to its tracks.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.album});

  final OnlineAlbum album;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kind = album.kind == OnlineAlbumKind.show ? 'show' : 'album';
    return InkWell(
      onTap: () => openOnlineAlbum(context, album),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Artwork(path: null, url: album.imageUrl, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [?album.creator, kind].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Badge(album.source),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// A new release by the artist searched for; opens to its songs.
class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openRelease(context, release),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Artwork(path: null, url: release.coverUrl, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    release.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [release.type, release.date].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the page with [album]'s tracks.
void openOnlineAlbum(BuildContext context, OnlineAlbum album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => OnlineAlbumScreen(album: album)),
  );
}

/// Which service a result is from.
class _Badge extends StatelessWidget {
  const _Badge(this.source);

  final OnlineSourceId source;

  @override
  Widget build(BuildContext context) => Text(
    source.badge,
    style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: context.noc.textTertiary, letterSpacing: 0.6),
  );
}

/// Opens the same search in Spotify and in YouTube Music, in their apps.
class _ElsewhereButtons extends ConsumerWidget {
  const _ElsewhereButtons({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(
      Future<bool> Function(LinkOpener open, String words) search,
      String name,
    ) async {
      final opened = await search(ref.read(linkOpenerProvider), query);
      if (!opened && context.mounted) say(context, "Couldn't open $name.");
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: PillButton(
                label: 'Search on Spotify',
                onTap: () => open(searchOnSpotify, 'Spotify'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PillButton(
                label: 'Search on YouTube Music',
                onTap: () => open(searchOnYouTubeMusic, 'YouTube Music'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// The searches made lately, newest first, each a tap away from being run
/// again.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.searches,
    required this.onSearch,
    required this.onClear,
  });

  final List<String> searches;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Recent searches', style: text.titleMedium),
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
        for (final search in searches)
          ListTile(
            leading: Icon(Icons.history_rounded, color: palette.textTertiary),
            title: Text(
              search,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge,
            ),
            onTap: () => onSearch(search),
          ),
      ],
    );
  }
}
