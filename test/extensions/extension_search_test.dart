import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/extensions/extension_channel.dart';
import 'package:noctune/features/extensions/extension_controller.dart';
import 'package:noctune/features/extensions/extension_models.dart';
import 'package:noctune/features/extensions/extensions_screen.dart';
import 'package:noctune/features/lyrics/lyrics_source.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeExtensionChannel extends ExtensionChannel {
  _FakeExtensionChannel({
    List<InstalledExtension>? initial,
    this.searchResults = const [],
    this.lyricsText,
  }) : _installed = List<InstalledExtension>.of(initial ?? const []);

  List<InstalledExtension> _installed;
  final List<ExtensionTrackResult> searchResults;
  final String? lyricsText;
  final List<String> downloadedTitles = [];

  @override
  bool get isSupported => true;

  @override
  Future<List<InstalledExtension>> init({required String musicDir}) async =>
      List.unmodifiable(_installed);

  @override
  Future<List<InstalledExtension>> list() async =>
      List.unmodifiable(_installed);

  @override
  Future<List<InstalledExtension>> installFile(String path) async {
    _installed = [
      ..._installed,
      const InstalledExtension(
        id: 'mornye-lossless',
        name: 'mornye-lossless',
        displayName: 'Mornye Lossless',
        version: '1.2.0',
        hasMetadataProvider: true,
        hasDownloadProvider: true,
        hasLyricsProvider: true,
      ),
    ];
    return List.unmodifiable(_installed);
  }

  @override
  Future<List<InstalledExtension>> setEnabled(String id, bool enabled) async {
    _installed = [
      for (final ext in _installed)
        if (ext.id == id)
          InstalledExtension(
            id: ext.id,
            name: ext.name,
            displayName: ext.displayName,
            version: ext.version,
            description: ext.description,
            enabled: enabled,
            hasMetadataProvider: ext.hasMetadataProvider,
            hasDownloadProvider: ext.hasDownloadProvider,
            hasLyricsProvider: ext.hasLyricsProvider,
            hasCustomSearch: ext.hasCustomSearch,
            hasUrlHandler: ext.hasUrlHandler,
          )
        else
          ext,
    ];
    return List.unmodifiable(_installed);
  }

  @override
  Future<List<InstalledExtension>> remove(String id) async {
    _installed = [
      for (final ext in _installed)
        if (ext.id != id) ext,
    ];
    return List.unmodifiable(_installed);
  }

  @override
  Future<List<ExtensionTrackResult>> search(
    String query, {
    int limit = 20,
    String? filter,
    String? providerId,
  }) async {
    return [
      for (final item in searchResults)
        if ((providerId == null ||
                providerId == 'all' ||
                item.providerId == providerId) &&
            (filter == null ||
                filter == 'all' ||
                (filter == 'tracks' && item.isTrack) ||
                (filter == 'albums' && item.isAlbum) ||
                (filter == 'artists' && item.isArtist)) &&
            (item.title.toLowerCase().contains(query.toLowerCase()) ||
                item.artist.toLowerCase().contains(query.toLowerCase())))
          item,
    ];
  }

  @override
  Future<String?> download(
    ExtensionTrackResult track, {
    required String musicDir,
    String? providerId,
    String? quality,
  }) async {
    downloadedTitles.add('${track.title}:${quality ?? 'default'}');
    return '$musicDir/Extensions/${track.title}.flac';
  }

  @override
  Future<String?> fetchLyrics({
    required String title,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    return lyricsText;
  }
}

class _FakeHandler extends Fake implements NocAudioHandler {
  final played = <String>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    played.add(tracks[initialIndex].title);
  }
}

Track _track(int id, String title) => Track(
  id: id,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: 'Aurora',
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'Search lists extension results below library matches and downloads on tap',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final channel = _FakeExtensionChannel(
        initial: const [
          InstalledExtension(
            id: 'qobuz-ext',
            name: 'qobuz-ext',
            displayName: 'Qobuz Lossless',
            version: '1.0.0',
            hasMetadataProvider: true,
            hasDownloadProvider: true,
          ),
        ],
        searchResults: const [
          ExtensionTrackResult(
            id: 'ext-1',
            title: 'Starlight FLAC',
            artist: 'Muse',
            album: 'Black Holes',
            duration: Duration(minutes: 4),
            providerId: 'qobuz-ext',
            providerName: 'Qobuz Lossless',
          ),
        ],
      );
      final library = [_track(1, 'Starlight Local')];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            audioHandlerProvider.overrideWithValue(_FakeHandler()),
            extensionChannelProvider.overrideWithValue(channel),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
            allTracksProvider.overrideWith((ref) => library),
            searchResultsProvider.overrideWith(
              (ref, query) => [
                for (final t in library)
                  if (t.title.toLowerCase().contains(query.toLowerCase())) t,
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildNocTheme(Brightness.dark, NocAccent.red),
            home: const Scaffold(body: SearchScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'starlight');
      await tester.pumpAndSettle();

      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Starlight Local'), findsOneWidget);
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('Starlight FLAC'), findsOneWidget);

      await tester.tap(find.byTooltip('Download Starlight FLAC'));
      await tester.pumpAndSettle();

      // Mornye-style format & service picker sheet appears before downloading.
      expect(find.text('Download from'), findsOneWidget);
      expect(find.text('Select format & quality'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker-quality-LOSSLESS')));
      await tester.pumpAndSettle();

      expect(channel.downloadedTitles, ['Starlight FLAC:LOSSLESS']);
      expect(
        find.text('Downloaded "Starlight FLAC" to library.'),
        findsOneWidget,
      );

      // Open the Download queue page from Search and verify the completed track is listed.
      await tester.tap(find.byTooltip('Download queue'));
      await tester.pumpAndSettle();

      expect(find.text('Download queue'), findsOneWidget);
      expect(find.text('COMPLETED (1)'), findsOneWidget);
      expect(find.text('Starlight FLAC'), findsOneWidget);

      await tester.tap(find.text('Clear finished'));
      await tester.pumpAndSettle();
      expect(find.text('No downloads in queue'), findsOneWidget);
    },
  );

  testWidgets('ExtensionsScreen shows installed extensions and toggles them', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final channel = _FakeExtensionChannel(
      initial: const [
        InstalledExtension(
          id: 'tidal-ext',
          name: 'tidal-ext',
          displayName: 'Tidal HiRes',
          version: '2.1.0',
          description: 'Lossless FLAC downloads',
          hasMetadataProvider: true,
          hasDownloadProvider: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          extensionChannelProvider.overrideWithValue(channel),
        ],
        child: MaterialApp(
          theme: buildNocTheme(Brightness.dark, NocAccent.red),
          home: const ExtensionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tidal HiRes'), findsOneWidget);
    expect(find.textContaining('v2.1.0 · Search · Download'), findsOneWidget);

    await tester.tap(find.byType(Switch).evaluate().isNotEmpty
        ? find.byType(Switch)
        : find.byWidgetPredicate((w) => w.runtimeType.toString() == 'CupertinoSwitch'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExtensionsScreen)),
    );
    expect(
      container.read(extensionControllerProvider).extensions.single.enabled,
      isFalse,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'loadLyrics falls back to an enabled lyrics extension and caches the LRC',
    () async {
      final db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      final repository = LibraryRepository(db);
      await repository.upsertTracks([_track(1, 'Runaway')]);
      final track = (await repository.tracks()).single;
      final channel = _FakeExtensionChannel(
        lyricsText: '[00:01.00] First line\n[00:05.00] Second line',
      );

      final loaded = await loadLyrics(
        track,
        repository,
        extensionChannel: channel,
      );

      expect(loaded, isNotNull);
      expect(loaded!.lyrics.lines, hasLength(2));
      expect(loaded.lyrics.lines.first.text, 'First line');
      // Cached into importedLyrics so future plays work offline.
      expect(
        await repository.importedLyrics(track.id),
        contains('First line'),
      );
    },
  );

  testWidgets(
    'Search filters by All, Songs, Albums, Artists and switches extension source',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final channel = _FakeExtensionChannel(
        initial: const [
          InstalledExtension(
            id: 'deezer',
            name: 'deezer',
            displayName: 'Deezer',
            version: '1.3.7',
            hasMetadataProvider: true,
            hasDownloadProvider: true,
            hasCustomSearch: true,
          ),
          InstalledExtension(
            id: 'jiosaavn',
            name: 'jiosaavn',
            displayName: 'JioSaavn',
            version: '1.0.8',
            hasMetadataProvider: true,
            hasDownloadProvider: true,
            hasCustomSearch: true,
          ),
        ],
        searchResults: const [
          ExtensionTrackResult(
            id: 'dz-track-1',
            title: 'Midnight Song',
            artist: 'Aurora',
            providerId: 'deezer',
            providerName: 'Deezer',
            itemType: 'track',
          ),
          ExtensionTrackResult(
            id: 'dz-album-1',
            title: 'Midnight Album',
            artist: 'Aurora',
            providerId: 'deezer',
            providerName: 'Deezer',
            itemType: 'album',
          ),
          ExtensionTrackResult(
            id: 'dz-artist-1',
            title: 'Midnight Artist',
            artist: 'Aurora',
            providerId: 'deezer',
            providerName: 'Deezer',
            itemType: 'artist',
          ),
          ExtensionTrackResult(
            id: 'js-track-1',
            title: 'Midnight Saavn',
            artist: 'Aurora',
            providerId: 'jiosaavn',
            providerName: 'JioSaavn',
            itemType: 'track',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            audioHandlerProvider.overrideWithValue(_FakeHandler()),
            extensionChannelProvider.overrideWithValue(channel),
            currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
            allTracksProvider.overrideWith((ref) => const <Track>[]),
            searchResultsProvider.overrideWith(
              (ref, query) => const <Track>[],
            ),
          ],
          child: MaterialApp(
            theme: buildNocTheme(Brightness.dark, NocAccent.red),
            home: const Scaffold(body: SearchScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Category chips All, Songs, Albums, Artists and search icon dropdown are shown.
      expect(find.byKey(const ValueKey('search-category-all')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-category-songs')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-category-albums')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-category-artists')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-provider-dropdown')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'midnight');
      await tester.pumpAndSettle();

      // Default source is Deezer (first active extension); All shows song, album, artist.
      expect(find.text('Midnight Song'), findsOneWidget);
      expect(find.text('Midnight Album'), findsOneWidget);
      expect(find.text('Midnight Artist'), findsOneWidget);
      expect(find.text('Midnight Saavn'), findsNothing);

      // Filter to Albums only.
      await tester.tap(find.byKey(const ValueKey('search-category-albums')));
      await tester.pumpAndSettle();
      expect(find.text('Midnight Album'), findsOneWidget);
      expect(find.text('Midnight Song'), findsNothing);

      // Switch back to Songs and switch extension to JioSaavn via the search icon dropdown.
      await tester.tap(find.byKey(const ValueKey('search-category-songs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-provider-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-source-jiosaavn')));
      await tester.pumpAndSettle();
      expect(find.text('Midnight Saavn'), findsOneWidget);
      expect(find.text('Midnight Song'), findsNothing);
    },
  );
}
