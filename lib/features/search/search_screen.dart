import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/noc_backdrop.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../extensions/download_format_picker.dart';
import '../extensions/extension_controller.dart';
import '../extensions/extension_downloads_screen.dart';
import '../extensions/extension_models.dart';
import '../home/taste_artists_shelf.dart';
import '../library/collection_screen.dart';
import '../library/track_menu.dart';
import '../library/track_tile.dart';
import 'search_history.dart';

/// Mornye-style search categories.
enum SearchCategory {
  all('All', 'all', Icons.grid_view_rounded),
  songs('Songs', 'tracks', Icons.music_note_rounded),
  albums('Albums', 'albums', Icons.album_rounded),
  artists('Artists', 'artists', Icons.person_rounded);

  const SearchCategory(this.label, this.filterId, this.icon);

  final String label;
  final String filterId;
  final IconData icon;
}

/// Special source selector values alongside individual extension IDs.
const _kSourceLibraryOnly = '__library__';
const _kSourceYtMusicOnline = 'ytmusic';

/// Searches the library and enabled Mornye extensions by Songs, Albums, and
/// Artists with quick extension switching.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  String _debouncedExtQuery = '';
  Timer? _extDebounce;
  final _focus = FocusNode();
  bool _wasShowing = false;
  SearchCategory _category = SearchCategory.all;
  String? _selectedSourceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _extDebounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final trimmed = value.trim();
    final wasEmpty = _query.trim().isEmpty;
    setState(() {
      _query = value;
      if (trimmed.isEmpty) {
        _extDebounce?.cancel();
        _debouncedExtQuery = '';
      } else if (wasEmpty) {
        // Run the first non-empty query immediately; debounce subsequent rapid edits.
        _debouncedExtQuery = trimmed;
      }
    });
    if (trimmed.isNotEmpty && !wasEmpty) {
      _extDebounce?.cancel();
      _extDebounce = Timer(const Duration(milliseconds: 260), () {
        if (mounted && _query.trim() == trimmed) {
          setState(() => _debouncedExtQuery = trimmed);
        }
      });
    }
  }

  void _flushExtQuery() {
    _extDebounce?.cancel();
    final trimmed = _query.trim();
    if (_debouncedExtQuery != trimmed) {
      setState(() => _debouncedExtQuery = trimmed);
    }
  }

  /// A search counts as made once it is sent from the keyboard or one of its
  /// results is played, not on every letter typed.
  void _remember() {
    _flushExtQuery();
    ref.read(searchHistoryProvider.notifier).add(_query);
  }

  void _searchAgain(String search) {
    _extDebounce?.cancel();
    _field.value = TextEditingValue(
      text: search,
      selection: TextSelection.collapsed(offset: search.length),
    );
    setState(() {
      _query = search;
      _debouncedExtQuery = search.trim();
    });
    _remember();
  }

  void _clearQuery() {
    _extDebounce?.cancel();
    _field.clear();
    setState(() {
      _query = '';
      _debouncedExtQuery = '';
    });
  }

  String _resolveActiveSource(
    List<InstalledExtension> searchExtensions, {
    required bool onlineSupported,
  }) {
    final current = _selectedSourceId;
    if (current == _kSourceLibraryOnly || current == _kSourceYtMusicOnline) {
      return current!;
    }
    if (current != null && searchExtensions.any((e) => e.id == current)) {
      return current;
    }
    if (searchExtensions.isNotEmpty) {
      // Default to the primary / highest-priority enabled search extension so
      // searches query a single fast provider (~250ms) just like Mornye.
      return searchExtensions.first.id;
    }
    if (onlineSupported) {
      return _kSourceYtMusicOnline;
    }
    return _kSourceLibraryOnly;
  }

  String _searchHint(
    String activeSource,
    List<InstalledExtension> searchExtensions,
  ) {
    if (activeSource == _kSourceLibraryOnly) {
      return 'Search tracks, artists, albums…';
    }
    if (activeSource == _kSourceYtMusicOnline) {
      return 'Search YouTube Music & library…';
    }
    final ext = searchExtensions
        .where((e) => e.id == activeSource)
        .firstOrNull;
    if (ext != null) {
      if (ext.searchPlaceholder.trim().isNotEmpty) {
        return ext.searchPlaceholder.trim();
      }
      return 'Search ${ext.displayName} & library…';
    }
    return 'Search tracks, artists, albums…';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final history = ref.watch(searchHistoryProvider);
    final extState = ref.watch(extensionControllerProvider);
    final onlineSupported = ref.watch(extensionChannelProvider).isSupported;
    final searchExtensions = extState.enabledSearchExtensions;
    final activeSource = _resolveActiveSource(
      searchExtensions,
      onlineSupported: onlineSupported,
    );
    final queueCount = extState.downloadQueue.length;
    final activeDownloads = extState.activeDownloadCount;
    final showProviderDropdown =
        searchExtensions.isNotEmpty || onlineSupported;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    onChanged: _onQueryChanged,
                    onSubmitted: (_) => _remember(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: _searchHint(activeSource, searchExtensions),
                      prefixIcon: !showProviderDropdown
                          ? const Icon(Icons.search_rounded)
                          : _SearchProviderDropdownButton(
                              activeSource: activeSource,
                              searchExtensions: searchExtensions,
                              onSelected: (sourceId) {
                                setState(() => _selectedSourceId = sourceId);
                                _flushExtQuery();
                              },
                            ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear search',
                              onPressed: _clearQuery,
                              icon: const Icon(Icons.close_rounded, size: 20),
                            )
                          : null,
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
                if (extState.extensions.isNotEmpty || queueCount > 0) ...[
                  const SizedBox(width: 8),
                  _DownloadQueueButton(
                    queueCount: queueCount,
                    activeCount: activeDownloads,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ExtensionDownloadsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          // Mornye-style category filter bar: All, Songs, Albums, Artists.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final cat in SearchCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SearchPillChip(
                      key: ValueKey('search-category-${cat.name}'),
                      label: cat.label,
                      icon: cat.icon,
                      selected: _category == cat,
                      onTap: () {
                        setState(() => _category = cat);
                        _flushExtQuery();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _query.trim().isNotEmpty
                ? _Results(
                    query: _query.trim(),
                    extQuery: _debouncedExtQuery.isNotEmpty
                        ? _debouncedExtQuery
                        : _query.trim(),
                    category: _category,
                    activeSource: activeSource,
                    hasExtensions:
                        (searchExtensions.isNotEmpty || onlineSupported) &&
                        activeSource != _kSourceLibraryOnly,
                    onPlayed: _remember,
                  )
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

class _SearchProviderDropdownButton extends StatelessWidget {
  const _SearchProviderDropdownButton({
    required this.activeSource,
    required this.searchExtensions,
    required this.onSelected,
  });

  final String activeSource;
  final List<InstalledExtension> searchExtensions;
  final ValueChanged<String> onSelected;

  IconData _activeIcon() {
    if (activeSource == _kSourceLibraryOnly) {
      return Icons.library_music_rounded;
    }
    return Icons.search_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: PopupMenuButton<String>(
        key: const ValueKey('search-provider-dropdown'),
        tooltip: 'Change search provider',
        offset: const Offset(0, 44),
        color: palette.glassSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.glassBorder),
        ),
        onSelected: onSelected,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_activeIcon(), size: 20, color: palette.accent),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
          ],
        ),
        itemBuilder: (context) => [
          for (final ext in searchExtensions)
            PopupMenuItem<String>(
              key: ValueKey('search-source-${ext.id}'),
              value: ext.id,
              child: Row(
                children: [
                  Icon(
                    Icons.extension_rounded,
                    size: 18,
                    color: activeSource == ext.id
                        ? palette.accent
                        : palette.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ext.displayName,
                      style: TextStyle(
                        fontWeight: activeSource == ext.id
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (activeSource == ext.id)
                    Icon(Icons.check_rounded, size: 18, color: palette.accent),
                ],
              ),
            ),
          PopupMenuItem<String>(
            key: const ValueKey('search-source-ytmusic-online'),
            value: _kSourceYtMusicOnline,
            child: Row(
              children: [
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 18,
                  color: activeSource == _kSourceYtMusicOnline
                      ? palette.accent
                      : palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'YouTube Music (Online)',
                    style: TextStyle(
                      fontWeight: activeSource == _kSourceYtMusicOnline
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (activeSource == _kSourceYtMusicOnline)
                  Icon(Icons.check_rounded, size: 18, color: palette.accent),
              ],
            ),
          ),
          PopupMenuItem<String>(
            key: const ValueKey('search-source-library'),
            value: _kSourceLibraryOnly,
            child: Row(
              children: [
                Icon(
                  Icons.library_music_rounded,
                  size: 18,
                  color: activeSource == _kSourceLibraryOnly
                      ? palette.accent
                      : palette.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Library only',
                    style: TextStyle(
                      fontWeight: activeSource == _kSourceLibraryOnly
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (activeSource == _kSourceLibraryOnly)
                  Icon(Icons.check_rounded, size: 18, color: palette.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadQueueButton extends StatelessWidget {
  const _DownloadQueueButton({
    required this.queueCount,
    required this.activeCount,
    required this.onTap,
  });

  final int queueCount;
  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Pressable(
      semanticLabel: 'Download queue',
      onTap: onTap,
      child: Tooltip(
        message: 'Download queue',
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: activeCount > 0 ? palette.accent : palette.glass,
            shape: StadiumBorder(
              side: BorderSide(
                color: activeCount > 0 ? palette.accent : palette.glassBorder,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.downloading_rounded,
                size: 20,
                color: activeCount > 0
                    ? palette.onAccent
                    : palette.textPrimary,
              ),
              if (queueCount > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$queueCount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: activeCount > 0
                        ? palette.onAccent
                        : palette.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPillChip extends StatelessWidget {
  const _SearchPillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  }) : compact = false;

  final String label;
  final IconData? icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final fg = selected ? palette.onAccent : palette.textSecondary;
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 6 : 8,
        ),
        decoration: ShapeDecoration(
          color: selected ? palette.accent : palette.glass,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? palette.accent : palette.glassBorder,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 14 : 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The library's and selected extension's matches for [query].
class _Results extends ConsumerWidget {
  const _Results({
    required this.query,
    required this.extQuery,
    required this.category,
    required this.activeSource,
    required this.hasExtensions,
    required this.onPlayed,
  });

  final String query;
  final String extQuery;
  final SearchCategory category;
  final String activeSource;
  final bool hasExtensions;
  final VoidCallback onPlayed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(searchResultsProvider(query));
    final allLibrary = ref.watch(allTracksProvider).value ?? const <Track>[];
    final currentId = ref.watch(currentTrackIdProvider);
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );

    final extSearch = hasExtensions
        ? ref.watch(
            extensionFilteredSearchProvider((
              query: extQuery,
              filter: category.filterId,
              providerId: activeSource,
            )),
          )
        : const AsyncValue<List<ExtensionTrackResult>>.data([]);

    if (!local.hasValue) return const _Progress('Searching your library…');

    final rawLocalTracks = local.value ?? const <Track>[];
    final localTracks =
        (category == SearchCategory.all || category == SearchCategory.songs)
        ? rawLocalTracks
        : const <Track>[];

    // Local album and artist matches from the library.
    final lowerQ = query.toLowerCase();
    final localAlbums = <String, Track>{};
    final localArtists = <String, Track>{};
    if (category == SearchCategory.all || category == SearchCategory.albums) {
      for (final t in allLibrary) {
        final alb = t.album?.trim() ?? '';
        if (alb.isNotEmpty && alb.toLowerCase().contains(lowerQ)) {
          localAlbums.putIfAbsent(alb, () => t);
        }
      }
    }
    if (category == SearchCategory.artists) {
      for (final t in allLibrary) {
        final art = t.artist?.trim() ?? '';
        if (art.isNotEmpty && art.toLowerCase().contains(lowerQ)) {
          localArtists.putIfAbsent(art, () => t);
        }
      }
    }

    final extResults = extSearch.value ?? const <ExtensionTrackResult>[];
    final extSongs = [
      for (final item in extResults)
        if (item.isTrack &&
            (category == SearchCategory.all ||
                category == SearchCategory.songs))
          item,
    ];
    final extAlbums = [
      for (final item in extResults)
        if (item.isAlbum &&
            (category == SearchCategory.all ||
                category == SearchCategory.albums))
          item,
    ];
    final extArtists = [
      for (final item in extResults)
        if (item.isArtist &&
            (category == SearchCategory.all ||
                category == SearchCategory.artists))
          item,
    ];

    final hasLocalMatches =
        localTracks.isNotEmpty ||
        localAlbums.isNotEmpty ||
        localArtists.isNotEmpty;
    final hasExtMatches =
        extSongs.isNotEmpty || extAlbums.isNotEmpty || extArtists.isNotEmpty;

    if (!hasLocalMatches && !hasExtensions) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        title: 'No matches',
        message: 'Nothing in your library matches "$query".',
      );
    }
    if (!hasLocalMatches && !extSearch.isLoading && !hasExtMatches) {
      return EmptyState(
        icon: Icons.music_off_outlined,
        title: 'No matches',
        message: 'Nothing in your library matches "$query".',
      );
    }

    return ListView(
      children: [
        if (hasLocalMatches) ...[
          const _Heading('In your library'),
          for (final entry in localArtists.entries)
            _LocalCollectionTile(
              title: entry.key,
              subtitle: 'Artist · In your library',
              artPath: entry.value.artPath,
              circular: true,
              onTap: () {
                onPlayed();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GroupScreen(group: TrackGroup.artist, name: entry.key),
                  ),
                );
              },
            ),
          for (final entry in localAlbums.entries)
            _LocalCollectionTile(
              title: entry.key,
              subtitle:
                  'Album · ${entry.value.artist ?? 'Unknown artist'} · In your library',
              artPath: entry.value.artPath,
              onTap: () {
                onPlayed();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        GroupScreen(group: TrackGroup.album, name: entry.key),
                  ),
                );
              },
            ),
          for (final (index, track) in localTracks.indexed)
            TrackTile(
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
        ],
        if (hasExtensions) ...[
          if (hasExtMatches) const _Heading('Extensions'),
          if (extArtists.isNotEmpty) ...[
            if (category == SearchCategory.all)
              const _SubHeading('Artists'),
            for (final artist in extArtists)
              _ExtensionCollectionTile(
                result: artist,
                circular: true,
                onTap: () {
                  onPlayed();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ExtensionArtistScreen(artist: artist),
                    ),
                  );
                },
              ),
          ],
          if (extAlbums.isNotEmpty) ...[
            if (category == SearchCategory.all)
              const _SubHeading('Albums'),
            for (final album in extAlbums)
              _ExtensionCollectionTile(
                result: album,
                onTap: () {
                  onPlayed();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ExtensionAlbumScreen(album: album),
                    ),
                  );
                },
              ),
          ],
          if (extSongs.isNotEmpty) ...[
            if (category == SearchCategory.all &&
                (extAlbums.isNotEmpty || extArtists.isNotEmpty))
              const _SubHeading('Songs'),
            for (final extTrack in extSongs)
              _ExtensionResultTile(
                result: extTrack,
                queue: extSongs,
                libraryTracks: rawLocalTracks,
                onPlayed: onPlayed,
              ),
          ],
          if (extSearch.isLoading) const _Progress('Searching extensions…'),
        ],
      ],
    );
  }
}

class _LocalCollectionTile extends StatelessWidget {
  const _LocalCollectionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.artPath,
    this.circular = false,
  });

  final String title;
  final String subtitle;
  final String? artPath;
  final bool circular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(circular ? 24 : 10),
        child: Artwork(
          path: artPath,
          size: 48,
          radius: circular ? 24 : 10,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleMedium,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: palette.textSecondary),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: palette.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _ExtensionCollectionTile extends StatelessWidget {
  const _ExtensionCollectionTile({
    required this.result,
    required this.onTap,
    this.circular = false,
  });

  final ExtensionTrackResult result;
  final bool circular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final kindLabel = result.isArtist ? 'Artist' : 'Album';
    final parts = <String>[
      kindLabel,
      if (result.artist.isNotEmpty && !result.isArtist) result.artist,
      if (result.providerName.isNotEmpty) result.providerName,
    ];
    return ListTile(
      leading: _RemoteOrLocalCover(
        coverUrl: result.coverUrl,
        size: 48,
        circular: circular,
      ),
      title: Text(
        result.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleMedium,
      ),
      subtitle: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(color: palette.textSecondary),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: palette.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _RemoteOrLocalCover extends StatelessWidget {
  const _RemoteOrLocalCover({
    required this.coverUrl,
    required this.size,
    this.circular = false,
  });

  final String coverUrl;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final radius = circular ? size / 2 : 10.0;
    final fallback = Artwork(
      path: null,
      size: size,
      radius: radius,
    );
    if (coverUrl.isEmpty || !coverUrl.startsWith('http')) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _ExtensionResultTile extends ConsumerWidget {
  const _ExtensionResultTile({
    required this.result,
    required this.libraryTracks,
    required this.onPlayed,
    this.queue = const [],
  });

  final ExtensionTrackResult result;
  final List<ExtensionTrackResult> queue;
  final List<Track> libraryTracks;
  final VoidCallback onPlayed;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final selection = await showExtensionDownloadPicker(
      context,
      ref,
      title: result.title,
      artist: result.artist.isNotEmpty ? result.artist : result.providerName,
      coverUrl: result.coverUrl,
      recommendedProviderId: result.providerId,
    );
    if (selection == null || !context.mounted) return;
    onPlayed();
    try {
      final path = await ref
          .read(extensionControllerProvider.notifier)
          .downloadTrack(
            result,
            providerId: selection.providerId,
            quality: selection.qualityId,
          );
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
    final palette = context.noc;
    final extState = ref.watch(extensionControllerProvider);
    final isDownloading = extState.downloadingKeys.contains(result.uniqueKey);
    final savedPath = extState.downloadedPaths[result.uniqueKey];
    final allLibrary = ref.watch(allTracksProvider).value ?? libraryTracks;
    final currentItem = ref.watch(currentMediaItemProvider).value;
    final playing = ref.watch(
      playbackStateProvider.select((state) => state.value?.playing ?? false),
    );
    final localMatch = allLibrary.cast<Track?>().firstWhere(
      (t) =>
          t != null &&
          (t.uri == savedPath ||
              (t.title.toLowerCase() == result.title.toLowerCase() &&
                  (t.artist ?? '').toLowerCase() ==
                      result.artist.toLowerCase())),
      orElse: () => null,
    );

    final isCurrent =
        currentItem != null &&
        ((localMatch != null && currentItem.id == localMatch.uri) ||
            (currentItem.title.toLowerCase() == result.title.toLowerCase() &&
                (currentItem.artist ?? '').toLowerCase() ==
                    (result.artist.isNotEmpty
                            ? result.artist
                            : result.providerName)
                        .toLowerCase()));

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
      artPath:
          localMatch?.artPath ??
          (result.coverUrl.isNotEmpty ? result.coverUrl : null),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

    void handlePlayTap() {
      onPlayed();
      if (isCurrent) {
        final handler = ref.read(audioHandlerProvider);
        if (playing) {
          handler.pause();
        } else {
          handler.play();
        }
        return;
      }
      playOnlineExtensionTrack(context, ref, result, queue: queue);
    }

    return TrackTile(
      track: syntheticTrack,
      isCurrent: isCurrent,
      playing: playing,
      onTap: handlePlayTap,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('play-online-${result.uniqueKey}'),
            tooltip: isCurrent && playing
                ? 'Pause ${result.title}'
                : 'Play ${result.title}',
            onPressed: handlePlayTap,
            icon: Container(
              width: 34,
              height: 34,
              decoration: ShapeDecoration(
                color: isCurrent
                    ? palette.accent
                    : palette.glass,
                shape: CircleBorder(
                  side: BorderSide(
                    color: isCurrent ? palette.accent : palette.glassBorder,
                  ),
                ),
              ),
              child: Icon(
                isCurrent && playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 20,
                color: isCurrent ? palette.onAccent : palette.textPrimary,
              ),
            ),
          ),
          if (isDownloading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (localMatch != null || savedPath != null)
            IconButton(
              tooltip: 'Downloaded',
              onPressed: localMatch == null
                  ? null
                  : () {
                      ref.read(audioHandlerProvider).playTracks([localMatch]);
                      onPlayed();
                    },
              icon: Icon(
                Icons.download_done_rounded,
                color: palette.accent,
              ),
            )
          else
            IconButton(
              key: ValueKey('download-ext-${result.uniqueKey}'),
              tooltip: 'Download ${result.title}',
              onPressed: () => _download(context, ref),
              icon: const Icon(Icons.download_rounded),
            ),
        ],
      ),
    );
  }
}

/// Browses an extension album's tracks and lets the user download individual
/// songs or the entire album into their local library.
class _ExtensionAlbumScreen extends ConsumerStatefulWidget {
  const _ExtensionAlbumScreen({required this.album});

  final ExtensionTrackResult album;

  @override
  ConsumerState<_ExtensionAlbumScreen> createState() =>
      _ExtensionAlbumScreenState();
}

class _ExtensionAlbumScreenState extends ConsumerState<_ExtensionAlbumScreen> {
  ExtensionAlbumDetails? _details;
  bool _loading = true;
  String? _error;
  bool _downloadingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final details = await ref
          .read(extensionChannelProvider)
          .getAlbum(
            providerId: widget.album.providerId,
            albumId: widget.album.id,
          );
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
        if (details == null) {
          _error = 'Could not load album tracks from ${widget.album.providerName}.';
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _downloadAll(List<ExtensionTrackResult> tracks) async {
    if (_downloadingAll || tracks.isEmpty) return;
    final selection = await showExtensionDownloadPicker(
      context,
      ref,
      title: (_details?.name.isNotEmpty ?? false)
          ? _details!.name
          : widget.album.title,
      artist: (_details?.artist.isNotEmpty ?? false)
          ? _details!.artist
          : widget.album.artist,
      coverUrl: (_details?.coverUrl.isNotEmpty ?? false)
          ? _details!.coverUrl
          : widget.album.coverUrl,
      recommendedProviderId: widget.album.providerId,
    );
    if (selection == null || !mounted) return;
    setState(() => _downloadingAll = true);
    var downloaded = 0;
    try {
      for (final track in tracks) {
        try {
          final path = await ref
              .read(extensionControllerProvider.notifier)
              .downloadTrack(
                track,
                providerId: selection.providerId,
                quality: selection.qualityId,
              );
          if (path != null) downloaded++;
        } on Object {
          // Continue with remaining tracks.
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Downloaded $downloaded of ${tracks.length} tracks to library.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _downloadingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final tracks = _details?.tracks ?? const <ExtensionTrackResult>[];
    final coverUrl = (_details?.coverUrl.isNotEmpty ?? false)
        ? _details!.coverUrl
        : widget.album.coverUrl;
    final title = (_details?.name.isNotEmpty ?? false)
        ? _details!.name
        : widget.album.title;
    final artist = (_details?.artist.isNotEmpty ?? false)
        ? _details!.artist
        : widget.album.artist;

    return NocBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(title),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? EmptyState(
                icon: Icons.album_outlined,
                title: title,
                message: _error!,
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: Column(
                      children: [
                        _RemoteOrLocalCover(
                          coverUrl: coverUrl,
                          size: 180,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (artist.isNotEmpty) artist,
                            if (widget.album.providerName.isNotEmpty)
                              widget.album.providerName,
                            '${tracks.length} tracks',
                          ].join(' · '),
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                        if (tracks.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: PillButton(
                              icon: _downloadingAll
                                  ? Icons.hourglass_top_rounded
                                  : Icons.download_rounded,
                              label: _downloadingAll
                                  ? 'Downloading…'
                                  : 'Download album',
                              filled: true,
                              onTap: _downloadingAll
                                  ? () {}
                                  : () => _downloadAll(tracks),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final track in tracks)
                    _ExtensionResultTile(
                      result: track,
                      queue: tracks,
                      libraryTracks: const [],
                      onPlayed: () {},
                    ),
                ],
              ),
      ),
    );
  }
}

/// Browses an extension artist's top tracks and albums.
class _ExtensionArtistScreen extends ConsumerStatefulWidget {
  const _ExtensionArtistScreen({required this.artist});

  final ExtensionTrackResult artist;

  @override
  ConsumerState<_ExtensionArtistScreen> createState() =>
      _ExtensionArtistScreenState();
}

class _ExtensionArtistScreenState
    extends ConsumerState<_ExtensionArtistScreen> {
  ExtensionArtistDetails? _details;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final details = await ref
          .read(extensionChannelProvider)
          .getArtist(
            providerId: widget.artist.providerId,
            artistId: widget.artist.id,
          );
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
        if (details == null) {
          _error =
              'Could not load artist details from ${widget.artist.providerName}.';
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final topTracks = _details?.topTracks ?? const <ExtensionTrackResult>[];
    final albums = _details?.albums ?? const <ExtensionTrackResult>[];
    final coverUrl = (_details?.coverUrl.isNotEmpty ?? false)
        ? _details!.coverUrl
        : widget.artist.coverUrl;
    final name = (_details?.name.isNotEmpty ?? false)
        ? _details!.name
        : widget.artist.title;

    return NocBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(name),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? EmptyState(
                icon: Icons.person_outline_rounded,
                title: name,
                message: _error!,
              )
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      children: [
                        _RemoteOrLocalCover(
                          coverUrl: coverUrl,
                          size: 140,
                          circular: true,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.artist.providerName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.artist.providerName,
                            style: text.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (topTracks.isNotEmpty) ...[
                    const _Heading('Top songs'),
                    for (final track in topTracks)
                      _ExtensionResultTile(
                        result: track,
                        queue: topTracks,
                        libraryTracks: const [],
                        onPlayed: () {},
                      ),
                  ],
                  if (albums.isNotEmpty) ...[
                    const _Heading('Albums'),
                    for (final album in albums)
                      _ExtensionCollectionTile(
                        result: album,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  _ExtensionAlbumScreen(album: album),
                            ),
                          );
                        },
                      ),
                  ],
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

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: palette.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
