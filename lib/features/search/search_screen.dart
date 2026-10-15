import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/track.dart';
import '../library/track_menu.dart';
import '../library/track_tile.dart';
import '../online/online_playback.dart';
import '../online/online_search.dart';
import '../online/online_source.dart';
import 'search_history.dart';

/// Searches the library by title, artist, album and file name as you type,
/// and free music on Jamendo when the build has a Jamendo client id. With
/// nothing typed it lists the searches made lately, to run again.
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
    final online = ref.watch(_asksOnlineProvider);

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
                              'file name, and free music on Jamendo.'
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

/// Whether searches also go to Jamendo.
final _asksOnlineProvider = Provider<bool>(
  (ref) =>
      ref.watch(jamendoSourceProvider) != null &&
      ref.watch(onlineSearchEnabledProvider),
);

/// The library's matches, then Jamendo's. Each part loads and fails on its
/// own, so a slow or failing Jamendo never holds back the library.
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onPlayed});

  final String query;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(searchResultsProvider(query));
    final online = ref.watch(onlineSearchProvider(query));
    final asksOnline = ref.watch(_asksOnlineProvider);
    final currentId = ref.watch(currentTrackIdProvider);
    final currentUri = ref.watch(currentMediaItemProvider).value?.id;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    // Rebuilds the rows as downloads start, finish or fail.
    final downloads = ref.watch(onlineDownloadsProvider);
    final paths = ref.watch(appPathsProvider);

    final localTracks = local.value ?? const <Track>[];
    final results = online.value;
    final onlineTracks = results?.tracks ?? const <OnlineTrack>[];
    final offline = results?.failure == OnlineFailure.offline;
    final onlineLoading = asksOnline && online.isLoading;
    final note = onlineLoading || results == null ? null : _note(results);

    if (local.hasValue &&
        localTracks.isEmpty &&
        !onlineLoading &&
        onlineTracks.isEmpty &&
        results?.failure == null) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        title: 'No matches',
        message: asksOnline
            ? 'Nothing in your library or on Jamendo matches "$query".'
            : 'Nothing in your library matches "$query".',
      );
    }

    Future<void> playOnline(BuildContext context, int index) async {
      final outcome = await ref
          .read(onlinePlayerProvider)
          .play(onlineTracks, index, offline: offline);
      if (!context.mounted) return;
      if (outcome == OnlinePlayOutcome.started) {
        onPlayed();
        return;
      }
      _say(
        context,
        '${onlineTracks[index].title} needs an internet connection. '
        'Download it while online to play it offline.',
      );
    }

    Widget onlineRow(BuildContext context, int index) {
      final track = onlineTracks[index];
      final file = downloadedFile(paths, track);
      final downloaded = file.existsSync();
      final copy = Uri.file(file.path).toString();
      return Opacity(
        // Can't play right now: no connection and no copy on the device.
        opacity: offline && !downloaded ? 0.5 : 1,
        child: TrackTile(
          track: streamedTrack(track),
          isCurrent:
              currentUri == '${track.streamUrl}' ||
              (downloaded && currentUri == copy),
          playing: playing,
          onTap: () => playOnline(context, index),
          action: _DownloadAction(
            track: track,
            downloaded: downloaded,
            offline: offline,
            status: downloads[track.id],
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
      if (asksOnline) (_) => const _Heading('Free music on Jamendo'),
      if (onlineLoading) (_) => const _Progress('Searching Jamendo…'),
      if (note != null) (_) => _Note(note),
      if (!onlineLoading)
        for (var index = 0; index < onlineTracks.length; index++)
          (context) => onlineRow(context, index),
      if (!onlineLoading && onlineTracks.isNotEmpty)
        (_) => const _Note(
          'Free music shared by its artists under Creative Commons licences.',
        ),
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
    );
  }

  /// What to say above Jamendo's results, if anything.
  static String? _note(OnlineResults results) => switch (results.failure) {
    null when results.tracks.isEmpty => 'No free tracks on Jamendo match.',
    null => null,
    OnlineFailure.offline when results.fromCache =>
      "You're offline. These are from an earlier search; only downloaded "
          'songs can play.',
    OnlineFailure.offline =>
      "You're offline. Jamendo's results appear once you're connected; "
          'songs you downloaded are in your library.',
    OnlineFailure.rateLimited =>
      'Jamendo is busy right now. Try again in a minute.',
    OnlineFailure.unavailable => "Jamendo couldn't be reached right now.",
  };
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The end of an online result's row: a download button, or how it stands.
class _DownloadAction extends ConsumerWidget {
  const _DownloadAction({
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
          _say(
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
