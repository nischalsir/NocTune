import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/flex_type.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/pressable.dart';
import '../../data/models/track.dart';
import '../extensions/extension_controller.dart';
import '../extensions/extension_models.dart';
import 'home_feed.dart';

const _kSelectedTasteArtistsKey = 'selected_taste_artists';
const _kTasteOnboardingPromptedKey = 'taste_artists_prompted';

/// Curated artists across genres for first-time taste selection (Spotify /
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

/// Fetches online song recommendations from enabled extensions based on the
/// user's chosen favorite artists.
final onlineArtistSuggestionsProvider =
    FutureProvider.autoDispose<List<ExtensionTrackResult>>((ref) async {
      final hasExt = ref.watch(
        extensionControllerProvider.select(
          (state) => state.hasActiveSearchOrDownload,
        ),
      );
      final artists = ref.watch(tasteArtistsProvider);
      if (!hasExt || artists.isEmpty) return const [];

      final channel = ref.watch(extensionChannelProvider);
      final combined = <ExtensionTrackResult>[];
      final seenKeys = <String>{};

      for (final artist in artists.take(4)) {
        final results = await channel.search(
          artist,
          limit: 12,
          filter: 'tracks',
        );
        for (final item in results) {
          if (item.isTrack &&
              seenKeys.add('${item.title.toLowerCase()}:${item.artist.toLowerCase()}')) {
            combined.add(item);
          }
        }
      }
      return combined;
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
          title: 'Choose artists & genres you like',
          actions: [
            PillButton(
              label: current.isEmpty
                  ? 'Save'
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
              label: 'Later',
              onTap: () async {
                await ref
                    .read(sharedPreferencesProvider)
                    .setBool(_kTasteOnboardingPromptedKey, true);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
          children: [
            Text(
              'Pick your favourite artists across genres to get instant online '
              'song suggestions on Home.',
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

///Plays an [ExtensionTrackResult] online immediately via `resolvePlayableUri`.
Future<void> playOnlineExtensionTrack(
  BuildContext context,
  WidgetRef ref,
  ExtensionTrackResult result,
) async {
  final allLibrary = ref.read(allTracksProvider).value ?? const <Track>[];
  final extState = ref.read(extensionControllerProvider);
  final savedPath = extState.downloadedPaths[result.uniqueKey];
  final localMatch = allLibrary.cast<Track?>().firstWhere(
    (t) =>
        t != null &&
        (t.uri == savedPath ||
            (t.title.toLowerCase() == result.title.toLowerCase() &&
                (t.artist ?? '').toLowerCase() ==
                    result.artist.toLowerCase())),
    orElse: () => null,
  );
  if (localMatch != null) {
    await ref.read(audioHandlerProvider).playTracks([localMatch]);
    return;
  }

  if (context.mounted) {
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
    final uri = await ref
        .read(extensionControllerProvider.notifier)
        .resolvePlayableUri(result);
    if (uri == null || uri.isEmpty) {
      throw StateError('No playable stream found for "${result.title}".');
    }
    final playable = Track(
      id: 0,
      uri: uri,
      fileName: result.title,
      folder: '',
      title: result.title,
      artist: result.artist.isNotEmpty ? result.artist : result.providerName,
      album: result.album.isNotEmpty ? result.album : result.providerName,
      duration: result.duration,
      artPath: result.coverUrl.isNotEmpty ? result.coverUrl : null,
      dateAdded: DateTime.now(),
      dateModified: DateTime.now(),
    );
    await ref.read(audioHandlerProvider).playTracks([playable]);
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not play track: $e')));
  }
}

/// Home shelf displaying Spotify/LastWave-style artist & genre onboarding and
/// playable online suggestions using NocTune's existing [HomeShelf] UI.
class HomeOnlineSuggestionsSection extends ConsumerStatefulWidget {
  const HomeOnlineSuggestionsSection({super.key});

  @override
  ConsumerState<HomeOnlineSuggestionsSection> createState() =>
      _HomeOnlineSuggestionsSectionState();
}

class _HomeOnlineSuggestionsSectionState
    extends ConsumerState<HomeOnlineSuggestionsSection> {
  bool _checkedOnboarding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedOnboarding) return;
    _checkedOnboarding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasExt = ref
          .read(extensionControllerProvider)
          .hasActiveSearchOrDownload;
      final prefs = ref.read(sharedPreferencesProvider);
      final alreadyPrompted =
          prefs.getBool(_kTasteOnboardingPromptedKey) ?? false;
      final artists = ref.read(tasteArtistsProvider);
      if (hasExt && !alreadyPrompted && artists.isEmpty) {
        showTasteArtistPickerDialog(context, ref);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasExt = ref.watch(
      extensionControllerProvider.select(
        (state) => state.hasActiveSearchOrDownload,
      ),
    );
    final selectedArtists = ref.watch(tasteArtistsProvider);
    if (!hasExt && selectedArtists.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final suggestionsAsync = ref.watch(onlineArtistSuggestionsProvider);
    final suggestions =
        suggestionsAsync.value ?? const <ExtensionTrackResult>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Pressable(
                        semanticLabel: 'Choose artists & genres',
                        onTap: () => showTasteArtistPickerDialog(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: ShapeDecoration(
                            color: context.feedPanel,
                            shape: StadiumBorder(side: context.feedRim),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 15,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                selectedArtists.isEmpty
                                    ? 'Choose artists & genres'
                                    : 'Artists (${selectedArtists.length})',
                                style: FlexType.labelLarge.copyWith(
                                  fontSize: 13,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      for (final artist in selectedArtists) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: ShapeDecoration(
                            color: context.feedPanel,
                            shape: StadiumBorder(side: context.feedRim),
                          ),
                          child: Text(
                            artist,
                            style: FlexType.labelMedium.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty)
          HomeShelf(
            title: 'Suggested for you',
            onSeeAll: () => showTasteArtistPickerDialog(context, ref),
            items: [
              for (final item in suggestions)
                (
                  artPath: item.coverUrl.isNotEmpty ? item.coverUrl : null,
                  title: item.title,
                  subtitle: item.artist.isNotEmpty
                      ? item.artist
                      : item.providerName,
                  onTap: () => playOnlineExtensionTrack(context, ref, item),
                ),
            ],
          )
        else if (suggestionsAsync.isLoading && selectedArtists.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading suggestions for ${selectedArtists.join(', ')}…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
