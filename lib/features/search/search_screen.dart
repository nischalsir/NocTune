import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/track.dart';
import '../extensions/extension_controller.dart';
import '../extensions/extension_models.dart';
import '../library/track_menu.dart';
import '../library/track_tile.dart';
import 'search_history.dart';

/// Searches the library by title, artist, album and file name as you type.
/// Everything stays on the device. With nothing typed it lists the searches
/// made lately, to run again.
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
                    message:
                        'Find a track by its title, artist, album or '
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

/// The library's matches for [query].
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onPlayed});

  final String query;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(searchResultsProvider(query));
    final currentId = ref.watch(currentTrackIdProvider);
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final hasExtensions = ref.watch(
      extensionControllerProvider.select(
        (state) => state.hasActiveSearchOrDownload,
      ),
    );
    final extSearch = hasExtensions
        ? ref.watch(extensionSearchResultsProvider(query))
        : const AsyncValue<List<ExtensionTrackResult>>.data([]);

    final tracks = local.value ?? const <Track>[];
    final extTracks = extSearch.value ?? const <ExtensionTrackResult>[];
    if (!local.hasValue) return const _Progress('Searching your library…');
    if (tracks.isEmpty && !hasExtensions) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        title: 'No matches',
        message: 'Nothing in your library matches "$query".',
      );
    }
    if (tracks.isEmpty && !extSearch.isLoading && extTracks.isEmpty) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        title: 'No matches',
        message: 'Nothing in your library matches "$query".',
      );
    }

    return ListView(
      children: [
        if (tracks.isNotEmpty) ...[
          const _Heading('In your library'),
          for (final (index, track) in tracks.indexed)
            TrackTile(
              track: track,
              isCurrent: track.id == currentId,
              playing: playing,
              onTap: () {
                ref
                    .read(audioHandlerProvider)
                    .playTracks(tracks, initialIndex: index);
                onPlayed();
              },
              onMenu: () => showTrackMenu(context, ref, track),
            ),
        ],
        if (hasExtensions) ...[
          if (extTracks.isNotEmpty) const _Heading('Extensions'),
          for (final extTrack in extTracks)
            _ExtensionResultTile(
              result: extTrack,
              libraryTracks: tracks,
              onPlayed: onPlayed,
            ),
          if (extSearch.isLoading) const _Progress('Searching extensions…'),
        ],
      ],
    );
  }
}

class _ExtensionResultTile extends ConsumerWidget {
  const _ExtensionResultTile({
    required this.result,
    required this.libraryTracks,
    required this.onPlayed,
  });

  final ExtensionTrackResult result;
  final List<Track> libraryTracks;
  final VoidCallback onPlayed;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    onPlayed();
    try {
      final path = await ref
          .read(extensionControllerProvider.notifier)
          .downloadTrack(result);
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Downloaded "${result.title}" to library.')),
          );
      }
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extState = ref.watch(extensionControllerProvider);
    final isDownloading = extState.downloadingKeys.contains(result.uniqueKey);
    final savedPath = extState.downloadedPaths[result.uniqueKey];
    final allLibrary = ref.watch(allTracksProvider).value ?? libraryTracks;
    final localMatch = allLibrary.cast<Track?>().firstWhere(
      (t) =>
          t != null &&
          (t.uri == savedPath ||
              (t.title.toLowerCase() == result.title.toLowerCase() &&
                  (t.artist ?? '').toLowerCase() ==
                      result.artist.toLowerCase())),
      orElse: () => null,
    );

    final syntheticTrack = Track(
      id: localMatch?.id ?? 0,
      uri: localMatch?.uri ?? savedPath ?? '',
      fileName: result.title,
      folder: '',
      title: result.title,
      artist: result.artist.isNotEmpty ? result.artist : result.providerName,
      album: result.album.isNotEmpty
          ? '${result.album} · ${result.providerName}'
          : result.providerName,
      duration: result.duration,
      artPath: localMatch?.artPath,
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

    return TrackTile(
      track: syntheticTrack,
      onTap: () {
        if (localMatch != null) {
          ref.read(audioHandlerProvider).playTracks([localMatch]);
          onPlayed();
        } else if (!isDownloading) {
          _download(context, ref);
        }
      },
      action: isDownloading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : localMatch != null || savedPath != null
          ? IconButton(
              tooltip: 'Downloaded',
              onPressed: localMatch == null
                  ? null
                  : () {
                      ref.read(audioHandlerProvider).playTracks([localMatch]);
                      onPlayed();
                    },
              icon: const Icon(Icons.download_done_rounded),
            )
          : IconButton(
              tooltip: 'Download ${result.title}',
              onPressed: () => _download(context, ref),
              icon: const Icon(Icons.download_rounded),
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
