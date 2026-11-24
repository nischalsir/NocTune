import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/artwork.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../extensions/download_format_picker.dart';
import '../extensions/extension_controller.dart';
import '../extensions/extension_models.dart';
import '../playback/playback_mapping.dart';

const _kSelectedTasteArtistsKey = 'selected_taste_artists';
const _kTasteOnboardingPromptedKey = 'taste_artists_prompted';

/// Curated artists across genres for optional taste tuning (Spotify /
/// LastWave style).
const kCuratedGenreArtists = <({String name, String genre})>[
  (name: 'The Weeknd', genre: 'Pop & R&B'),
  (name: 'Arijit Singh', genre: 'Bollywood & Desi'),
  (name: 'Drake', genre: 'Hip-Hop & Rap'),
  (name: 'Taylor Swift', genre: 'Pop'),
  (name: 'Karan Aujla', genre: 'Bollywood & Desi'),
  (name: 'Billie Eilish', genre: 'Pop & Indie'),
  (name: 'Coldplay', genre: 'Rock & Indie'),
  (name: 'A.R. Rahman', genre: 'Bollywood & Desi'),
  (name: 'Kendrick Lamar', genre: 'Hip-Hop & Rap'),
  (name: 'Lana Del Rey', genre: 'Pop & Indie'),
  (name: 'Diljit Dosanjh', genre: 'Bollywood & Desi'),
  (name: 'Travis Scott', genre: 'Hip-Hop & Rap'),
  (name: 'Daft Punk', genre: 'Electronic'),
  (name: 'Anuv Jain', genre: 'Bollywood & Desi'),
  (name: 'Arctic Monkeys', genre: 'Rock & Indie'),
  (name: 'SZA', genre: 'Pop & R&B'),
  (name: 'Post Malone', genre: 'Pop & Hip-Hop'),
  (name: 'BTS', genre: 'K-Pop'),
  (name: 'Eminem', genre: 'Hip-Hop & Rap'),
  (name: 'Pritam', genre: 'Bollywood & Desi'),
  (name: 'Linkin Park', genre: 'Rock & Indie'),
  (name: 'Alan Walker', genre: 'Electronic'),
  (name: 'Shreya Ghoshal', genre: 'Bollywood & Desi'),
  (name: 'Joji', genre: 'Lo-Fi & R&B'),
];

const kTasteGenres = <String>[
  'All',
  'Pop',
  'Bollywood & Desi',
  'Hip-Hop & Rap',
  'Rock & Indie',
  'Pop & R&B',
  'Electronic',
  'K-Pop',
  'Lo-Fi & R&B',
];

class TasteArtistsController extends Notifier<List<String>> {
  @override
  List<String> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getStringList(_kSelectedTasteArtistsKey) ?? const [];
  }

  Future<void> setArtists(List<String> artists) async {
    final cleaned = [
      for (final a in artists)
        if (a.trim().isNotEmpty) a.trim(),
    ];
    state = cleaned;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(_kSelectedTasteArtistsKey, cleaned);
    await prefs.setBool(_kTasteOnboardingPromptedKey, true);
  }
}

final tasteArtistsProvider =
    NotifierProvider<TasteArtistsController, List<String>>(
      TasteArtistsController.new,
    );

class _DiscoveryRefreshNonce extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _discoveryRefreshNonceProvider =
    NotifierProvider<_DiscoveryRefreshNonce, int>(_DiscoveryRefreshNonce.new);

class _HomeDiscoveryProviderFilter extends Notifier<String> {
  @override
  String build() => 'ytmusic';

  void select(String providerId) => state = providerId;
}

final _homeDiscoveryProviderFilterProvider =
    NotifierProvider<_HomeDiscoveryProviderFilter, String>(
      _HomeDiscoveryProviderFilter.new,
    );

class _HomeDiscoveryMoodChipFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? params) => state = params;
}

final _homeDiscoveryMoodChipFilterProvider =
    NotifierProvider<_HomeDiscoveryMoodChipFilter, String?>(
      _HomeDiscoveryMoodChipFilter.new,
    );

bool _isUsableArtistName(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s.length < 2) return false;
  final lower = s.toLowerCase();
  return lower != 'unknown' &&
      lower != 'unknown artist' &&
      lower != '<unknown>' &&
      lower != 'various artists';
}

/// Automatically builds a LastWave-Native / Mornye style Home Discovery Feed
/// from the user's real listening history (recent plays, most-played tracks,
/// favourites, top library artists) combined with optional user-selected taste
/// artists, without requiring manual setup.
final homeDiscoveryFeedProvider =
    FutureProvider.autoDispose<ExtensionHomeFeed>((ref) async {
      final channel = ref.watch(extensionChannelProvider);
      if (!channel.isSupported) return const ExtensionHomeFeed();

      final nonce = ref.watch(_discoveryRefreshNonceProvider);
      final selectedProviderId = ref.watch(_homeDiscoveryProviderFilterProvider);
      final selectedChipParams = ref.watch(_homeDiscoveryMoodChipFilterProvider);
      final tasteArtists = ref.watch(tasteArtistsProvider);
      final topArtists =
          ref.watch(topGroupsProvider(TrackGroup.artist)).value ?? const [];
      final recentTracks =
          ref.watch(recentlyPlayedProvider).value ?? const <Track>[];
      final mostPlayed =
          ref.watch(mostPlayedProvider).value ?? const <Track>[];
      final favorites = ref.watch(favoritesProvider).value ?? const <Track>[];

      final seedArtists = <String>[];
      final seenArtists = <String>{};
      void addArtist(String? raw) {
        if (raw == null) return;
        final primary = raw.split(RegExp(r'[,;&/]')).first.trim();
        if (!_isUsableArtistName(primary)) return;
        if (seenArtists.add(primary.toLowerCase())) {
          seedArtists.add(primary);
        }
      }

      for (final a in tasteArtists) {
        addArtist(a);
      }
      for (final g in topArtists.take(6)) {
        addArtist(g.name);
      }
      for (final t in recentTracks.take(6)) {
        addArtist(t.artist);
      }
      for (final t in favorites.take(4)) {
        addArtist(t.artist);
      }
      for (final t in mostPlayed.take(6)) {
        addArtist(t.artist);
      }

      if (seedArtists.isEmpty) {
        for (final entry in kCuratedGenreArtists.take(8)) {
          addArtist(entry.name);
        }
      }

      final seedTracks = <String>[];
      final seenTrackQueries = <String>{};
      void addTrackSeed(Track t) {
        final title = t.title.trim();
        final artist = (t.artist ?? '').split(RegExp(r'[,;&/]')).first.trim();
        if (title.isEmpty || !_isUsableArtistName(artist)) return;
        final q = '$title $artist';
        if (seenTrackQueries.add(q.toLowerCase())) {
          seedTracks.add(q);
        }
      }

      for (final t in recentTracks.take(4)) {
        addTrackSeed(t);
      }
      for (final t in favorites.take(3)) {
        addTrackSeed(t);
      }
      for (final t in mostPlayed.take(4)) {
        addTrackSeed(t);
      }

      // Rotate seed slice when the user taps Refresh so each refresh surfaces fresh tracks.
      List<String> rotate(List<String> list, int offset) {
        if (list.length <= 1 || offset == 0) return list;
        final shift = offset % list.length;
        return [...list.sublist(shift), ...list.sublist(0, shift)];
      }

      final activeArtists = rotate(seedArtists, nonce * 2).take(5).toList();
      final activeTracks = rotate(seedTracks, nonce).take(3).toList();

      final nativeFeed = await channel.getHomeFeed(
        seedArtists: activeArtists,
        seedTracks: activeTracks,
        providerId: selectedProviderId,
        chipParams: selectedChipParams,
      );
      if (!nativeFeed.isEmpty) {
        return nativeFeed;
      }

      // Fallback when channel.getHomeFeed is unimplemented (e.g. in widget test fakes):
      // query channel.search across seed artists with per-artist cap.
      final hasExt = ref.read(
        extensionControllerProvider.select(
          (state) => state.hasActiveSearchOrDownload,
        ),
      );
      final batches = <List<ExtensionTrackResult>>[];
      for (final artist in activeArtists.take(4)) {
        final res = await channel.search(
          artist,
          limit: 10,
          filter: 'tracks',
          providerId: hasExt ? null : 'ytmusic',
        );
        batches.add([for (final item in res) if (item.isTrack) item]);
      }
      final combined = <ExtensionTrackResult>[];
      final seenKeys = <String>{};
      final artistCounts = <String, int>{};
      final maxBatch = batches.fold<int>(
        0,
        (prev, b) => b.length > prev ? b.length : prev,
      );
      for (var i = 0; i < maxBatch; i++) {
        for (final batch in batches) {
          if (i >= batch.length) continue;
          final item = batch[i];
          final key =
              '${item.title.toLowerCase().trim()}:${item.artist.toLowerCase().trim()}';
          if (!seenKeys.add(key)) continue;
          final normArtist = item.artist
              .toLowerCase()
              .split(',')
              .first
              .trim();
          final count = artistCounts[normArtist] ?? 0;
          if (normArtist.isNotEmpty && count >= 2) continue;
          if (normArtist.isNotEmpty) artistCounts[normArtist] = count + 1;
          combined.add(item);
        }
      }
      return ExtensionHomeFeed(forYou: combined);
    });

/// Backwards-compatible provider exposing the primary personalized suggestions.
final onlineArtistSuggestionsProvider =
    FutureProvider.autoDispose<List<ExtensionTrackResult>>((ref) async {
      final feed = await ref.watch(homeDiscoveryFeedProvider.future);
      return feed.forYou;
    });

/// Opens the genre & artist picker dialog using NocTune's glass dialog style.
Future<void> showTasteArtistPickerDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = Set<String>.of(ref.read(tasteArtistsProvider));
  var selectedGenre = 'All';
  final customController = TextEditingController();

  await showNocDialog<void>(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        final palette = context.noc;
        final text = Theme.of(context).textTheme;
        final filtered = [
          for (final entry in kCuratedGenreArtists)
            if (selectedGenre == 'All' ||
                entry.genre.toLowerCase().contains(selectedGenre.toLowerCase()))
              entry,
        ];

        return NocDialogCard(
          title: 'Tune your taste & artists',
          actions: [
            PillButton(
              label: current.isEmpty
                  ? 'Use library history'
                  : 'Save (${current.length} selected)',
              filled: true,
              onTap: () async {
                await ref
                    .read(tasteArtistsProvider.notifier)
                    .setArtists(current.toList());
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            PillButton(
              label: 'Cancel',
              onTap: () {
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
          children: [
            Text(
              'NocTune automatically learns from your library & plays. You can '
              'also pin favourite artists here to boost them in your Home feed.',
              style: text.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final genre in kTasteGenres)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(genre),
                        selected: selectedGenre == genre,
                        onSelected: (_) =>
                            setModalState(() => selectedGenre = genre),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customController,
                    decoration: const InputDecoration(
                      hintText: 'Add any artist name…',
                      isDense: true,
                    ),
                    onSubmitted: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isNotEmpty) {
                        setModalState(() {
                          current.add(trimmed);
                          customController.clear();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add artist',
                  onPressed: () {
                    final trimmed = customController.text.trim();
                    if (trimmed.isNotEmpty) {
                      setModalState(() {
                        current.add(trimmed);
                        customController.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in filtered)
                      FilterChip(
                        label: Text('${entry.name} · ${entry.genre}'),
                        selected: current.contains(entry.name),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              current.add(entry.name);
                            } else {
                              current.remove(entry.name);
                            }
                          });
                        },
                      ),
                    for (final custom in current)
                      if (!kCuratedGenreArtists.any((e) => e.name == custom))
                        FilterChip(
                          label: Text(custom),
                          selected: true,
                          onSelected: (_) {
                            setModalState(() => current.remove(custom));
                          },
                        ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  customController.dispose();
}

Track? _findLocalTrackMatch(
  ExtensionTrackResult item,
  List<Track> allLibrary,
  Map<String, String> downloadedPaths,
) {
  final savedPath = downloadedPaths[item.uniqueKey];
  for (final t in allLibrary) {
    if ((savedPath != null && t.uri == savedPath) ||
        (t.title.toLowerCase() == item.title.toLowerCase() &&
            (t.artist ?? '').toLowerCase() == item.artist.toLowerCase())) {
      return t;
    }
  }
  return null;
}

Track _buildOnlinePlayableTrack(
  ExtensionTrackResult item,
  String uri, {
  String? resolvedCodec,
  int? resolvedBitrate,
  int? resolvedSampleRate,
  int? resolvedDurationMs,
}) {
  final savedDate = DateTime.now();
  final isSaavn = item.providerId == 'jiosaavn';
  final effectiveDuration =
      (resolvedDurationMs != null && resolvedDurationMs > 0)
      ? Duration(milliseconds: resolvedDurationMs)
      : item.duration;
  return Track(
    id: 0,
    uri: uri,
    fileName: item.title,
    folder: '${item.providerId}|${item.id}',
    title: item.title,
    artist: item.artist.isNotEmpty ? item.artist : item.providerName,
    album: item.album.isNotEmpty ? item.album : item.providerName,
    duration: effectiveDuration,
    artPath: item.coverUrl.isNotEmpty ? item.coverUrl : null,
    codec: (resolvedCodec != null && resolvedCodec.isNotEmpty)
        ? resolvedCodec
        : 'aac',
    bitrate: (resolvedBitrate != null && resolvedBitrate > 0)
        ? resolvedBitrate
        : (isSaavn ? 320000 : 128000),
    sampleRate: (resolvedSampleRate != null && resolvedSampleRate > 0)
        ? resolvedSampleRate
        : 44100,
    dateAdded: savedDate,
    dateModified: savedDate,
  );
}

Future<void> _appendRelatedOnlineTracks(
  WidgetRef ref, {
  required ExtensionTrackResult seed,
  required String query,
}) async {
  try {
    final channel = ref.read(extensionChannelProvider);
    final results = await channel.search(
      query,
      limit: 15,
      filter: 'tracks',
      providerId: seed.providerId.isNotEmpty ? seed.providerId : null,
    );
    final handler = ref.read(audioHandlerProvider);
    final allLibrary = ref.read(allTracksProvider).value ?? const <Track>[];
    final downloadedPaths = ref.read(extensionControllerProvider).downloadedPaths;
    for (final item in results) {
      if (!item.isTrack || item.uniqueKey == seed.uniqueKey) continue;
      final local = _findLocalTrackMatch(item, allLibrary, downloadedPaths);
      final nextTrack =
          local ??
          _buildOnlinePlayableTrack(
            item,
            downloadedPaths[item.uniqueKey] ?? channel.buildLazyStreamUri(item),
          );
      await handler.addQueueItem(mediaItemFromTrack(nextTrack));
    }
  } on Object {
    // Best-effort radio continuation when only 1 search result was played.
  }
}

/// Plays an [ExtensionTrackResult] online immediately via `resolvePlayableUri`
/// and queues the surrounding [queue] tracks so the Next and Previous buttons
/// advance seamlessly through online tracks.
Future<void> playOnlineExtensionTrack(
  BuildContext context,
  WidgetRef ref,
  ExtensionTrackResult result, {
  List<ExtensionTrackResult> queue = const [],
}) async {
  final allLibrary = ref.read(allTracksProvider).value ?? const <Track>[];
  final extState = ref.read(extensionControllerProvider);
  final channel = ref.read(extensionChannelProvider);

  final trackItems = [
    for (final item in queue)
      if (item.isTrack) item,
  ];
  final foundIdx = trackItems.indexWhere(
    (item) => item.uniqueKey == result.uniqueKey,
  );
  final activeQueue = foundIdx >= 0 ? trackItems : [result];
  final startIndex = foundIdx >= 0 ? foundIdx : 0;

  final localMatch = _findLocalTrackMatch(
    result,
    allLibrary,
    extState.downloadedPaths,
  );
  if (localMatch != null && activeQueue.length == 1) {
    await ref.read(audioHandlerProvider).playTracks([localMatch]);
    return;
  }

  if (localMatch == null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Loading "${result.title}"…'),
        ),
      );
  }
  try {
    final String primaryUri;
    if (localMatch != null) {
      primaryUri = localMatch.uri;
    } else {
      final resolved = await ref
          .read(extensionControllerProvider.notifier)
          .resolvePlayableUri(result);
      if (resolved == null || resolved.isEmpty) {
        throw StateError('No playable stream found for "${result.title}".');
      }
      primaryUri = resolved;
    }

    final latestDownloaded = ref
        .read(extensionControllerProvider)
        .downloadedPaths;
    final playableQueue = <Track>[
      for (final (idx, item) in activeQueue.indexed)
        if (idx == startIndex)
          localMatch ??
              _buildOnlinePlayableTrack(
                item,
                primaryUri,
                resolvedCodec: channel.lastResolvedCodec,
                resolvedBitrate: channel.lastResolvedBitrate,
                resolvedSampleRate: channel.lastResolvedSampleRate,
                resolvedDurationMs: channel.lastResolvedDurationMs,
              )
        else
          _findLocalTrackMatch(item, allLibrary, latestDownloaded) ??
              _buildOnlinePlayableTrack(
                item,
                latestDownloaded[item.uniqueKey] ??
                    channel.buildLazyStreamUri(item),
              ),
    ];

    await ref
        .read(audioHandlerProvider)
        .playTracks(playableQueue, initialIndex: startIndex);

    if (activeQueue.length == 1) {
      final seedQuery = result.artist.trim().isNotEmpty
          ? result.artist.trim()
          : result.title.trim();
      if (seedQuery.isNotEmpty) {
        unawaited(
          _appendRelatedOnlineTracks(ref, seed: result, query: seedQuery),
        );
      }
    }
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not play track: $e')));
  }
}

Future<void> _downloadSuggestedTrack(
  BuildContext context,
  WidgetRef ref,
  ExtensionTrackResult item,
) async {
  final selection = await showExtensionDownloadPicker(
    context,
    ref,
    title: item.title,
    artist: item.artist,
    coverUrl: item.coverUrl,
    recommendedProviderId: item.providerId,
  );
  if (selection == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Downloading "${item.title}" (${selection.qualityLabel}) via ${selection.providerName}…',
        ),
      ),
    );
  try {
    final savedPath = await ref
        .read(extensionControllerProvider.notifier)
        .downloadTrack(
          item,
          providerId: selection.providerId,
          quality: selection.qualityId,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            savedPath != null
                ? 'Downloaded "${item.title}" to library.'
                : 'Could not download "${item.title}".',
          ),
        ),
      );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}

/// Home discovery section displaying automatic LastWave-Native / Mornye style
/// personalized recommendations ("Discover for you") and live trending songs
/// ("Trending online") with one-tap online playback, direct download button,
/// refresh, and optional taste tuning.
class HomeOnlineSuggestionsSection extends ConsumerWidget {
  const HomeOnlineSuggestionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ref.watch(extensionChannelProvider);
    final hasExt = ref.watch(
      extensionControllerProvider.select(
        (state) => state.hasActiveSearchOrDownload,
      ),
    );
    final selectedArtists = ref.watch(tasteArtistsProvider);
    if (!channel.isSupported && !hasExt && selectedArtists.isEmpty) {
      return const SizedBox.shrink();
    }

    final feedAsync = ref.watch(homeDiscoveryFeedProvider);
    final feed = feedAsync.value ?? const ExtensionHomeFeed();
    final selectedProviderId = ref.watch(_homeDiscoveryProviderFilterProvider);
    final selectedChipParams = ref.watch(_homeDiscoveryMoodChipFilterProvider);
    final enabledProviders = ref.watch(
      extensionControllerProvider.select(
        (state) => state.enabledSearchExtensions,
      ),
    );
    final downloadingKeys = ref.watch(
      extensionControllerProvider.select((state) => state.downloadingKeys),
    );
    final downloadedPaths = ref.watch(
      extensionControllerProvider.select((state) => state.downloadedPaths),
    );

    if (feed.isEmpty && !feedAsync.isLoading) {
      return const SizedBox.shrink();
    }

    final providerOptions = <({String id, String label})>[
      (id: 'ytmusic', label: 'YouTube Music'),
      for (final ext in enabledProviders)
        if (ext.id != 'ytmusic' && ext.id != 'ytmusic-spotiflac')
          (id: ext.id, label: ext.displayName),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (providerOptions.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final p in providerOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('home-provider-chip-${p.id}'),
                        label: Text(p.label),
                        selected: selectedProviderId == p.id,
                        onSelected: (_) {
                          ref
                              .read(
                                _homeDiscoveryProviderFilterProvider.notifier,
                              )
                              .select(p.id);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (feed.chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: const ValueKey('home-mood-chip-all'),
                      label: const Text('All'),
                      selected: selectedChipParams == null,
                      onSelected: (_) {
                        ref
                            .read(_homeDiscoveryMoodChipFilterProvider.notifier)
                            .select(null);
                      },
                    ),
                  ),
                  for (final chip in feed.chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('home-mood-chip-${chip.title}'),
                        label: Text(chip.title),
                        selected: selectedChipParams == chip.params,
                        onSelected: (selected) {
                          ref
                              .read(
                                _homeDiscoveryMoodChipFilterProvider.notifier,
                              )
                              .select(selected ? chip.params : null);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (feed.forYou.isNotEmpty)
          _OnlineDiscoveryShelf(
            title: 'Discover for you',
            tracks: feed.forYou,
            downloadingKeys: downloadingKeys,
            downloadedPaths: downloadedPaths,
            isRefreshing: feedAsync.isLoading,
            onRefresh: () =>
                ref.read(_discoveryRefreshNonceProvider.notifier).bump(),
            onTuneTaste: () => showTasteArtistPickerDialog(context, ref),
          )
        else if (feedAsync.isLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Curating personalized recommendations…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (feed.becauseYouListenTo.isNotEmpty)
          _OnlineDiscoveryShelf(
            title: feed.becauseArtist.isNotEmpty
                ? 'Because you listen to ${feed.becauseArtist}'
                : 'Because you listen to your favourites',
            tracks: feed.becauseYouListenTo,
            downloadingKeys: downloadingKeys,
            downloadedPaths: downloadedPaths,
          ),
        if (feed.freshFinds.isNotEmpty)
          _OnlineDiscoveryShelf(
            title: 'Fresh finds',
            tracks: feed.freshFinds,
            downloadingKeys: downloadingKeys,
            downloadedPaths: downloadedPaths,
          ),
        if (feed.trending.isNotEmpty)
          _OnlineDiscoveryShelf(
            title: 'Trending online',
            tracks: feed.trending,
            downloadingKeys: downloadingKeys,
            downloadedPaths: downloadedPaths,
          ),
      ],
    );
  }
}

class _OnlineDiscoveryShelf extends ConsumerWidget {
  const _OnlineDiscoveryShelf({
    required this.title,
    required this.tracks,
    required this.downloadingKeys,
    required this.downloadedPaths,
    this.isRefreshing = false,
    this.onRefresh,
    this.onTuneTaste,
  });

  final String title;
  final List<ExtensionTrackResult> tracks;
  final Set<String> downloadingKeys;
  final Map<String, String> downloadedPaths;
  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final VoidCallback? onTuneTaste;

  static const _cover = 116.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.noc;
    final scaler = MediaQuery.textScalerOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlexType.titleLarge.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Refresh suggestions',
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                ),
              if (onTuneTaste != null)
                IconButton(
                  tooltip: 'Tune taste & artists',
                  onPressed: onTuneTaste,
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
              if (onRefresh == null && onTuneTaste == null)
                const SizedBox(height: 48),
            ],
          ),
        ),
        SizedBox(
          height: _cover + 8 + scaler.scale(20) + scaler.scale(18) + 6,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = tracks[index];
              final subtitle = item.artist.isNotEmpty
                  ? item.artist
                  : item.providerName;
              final isDownloading = downloadingKeys.contains(item.uniqueKey);
              final isDownloaded = downloadedPaths.containsKey(item.uniqueKey);

              return Semantics(
                button: true,
                label: [item.title, if (subtitle.isNotEmpty) subtitle].join(', '),
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => playOnlineExtensionTrack(
                    context,
                    ref,
                    item,
                    queue: tracks,
                  ),
                  onLongPress: () => _downloadSuggestedTrack(context, ref, item),
                  child: SizedBox(
                    width: _cover,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Artwork(
                              path: item.coverUrl.isNotEmpty
                                  ? item.coverUrl
                                  : null,
                              size: _cover,
                              radius: 16,
                            ),
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Material(
                                color: palette.background.withValues(
                                  alpha: 0.78,
                                ),
                                shape: CircleBorder(
                                  side: BorderSide(color: palette.glassBorder),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: (isDownloading || isDownloaded)
                                      ? null
                                      : () => _downloadSuggestedTrack(
                                          context,
                                          ref,
                                          item,
                                        ),
                                  child: SizedBox.square(
                                    dimension: 28,
                                    child: Center(
                                      child: isDownloading
                                          ? const SizedBox.square(
                                              dimension: 13,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              isDownloaded
                                                  ? Icons.check_rounded
                                                  : Icons.download_rounded,
                                              size: 16,
                                              color: isDownloaded
                                                  ? palette.accent
                                                  : palette.textPrimary,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FlexType.titleSmall.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlexType.bodySmall.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
