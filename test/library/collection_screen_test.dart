import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/core/widgets/artwork.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/collection_screen.dart';
import 'package:noctune/features/library/covers.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Stands in for the library's storage and records what it was asked to do.
class _FakeRepository extends Fake implements LibraryRepository {
  final calls = <String>[];

  @override
  Future<void> setPlaylistCover(int playlistId, String? path) async =>
      calls.add('cover $playlistId $path');

  @override
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async =>
      calls.add('add $playlistId $trackIds');
}

// Hands back a fixed picture in place of the system's picker.
class _FakeCovers extends Fake implements CoverStore {
  final discarded = <String?>[];

  @override
  Future<String?> pick() async => '/covers/mine.jpg';

  @override
  Future<void> discard(String? path) async => discarded.add(path);
}

class _FakeHandler extends Fake implements NocAudioHandler {
  final calls = <String>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async =>
      calls.add('play ${tracks[initialIndex].title} of ${tracks.length}');

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async =>
      calls.add('shuffle ${shuffleMode.name}');
}

Track _track(int id, String title, {String? art, int minutes = 3}) => Track(
  id: id,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: 'Aurora',
  album: 'Skyline',
  duration: Duration(minutes: minutes),
  artPath: art,
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

final _playlist = Playlist(
  id: 4,
  name: 'Night drive',
  createdAt: DateTime(2026),
  trackCount: 3,
);

void main() {
  final album = [
    _track(1, 'One', art: '/art/a.jpg'),
    _track(2, 'Two', art: '/art/b.jpg', minutes: 62),
    _track(3, 'Three', art: '/art/c.jpg'),
    _track(4, 'Four', art: '/art/a.jpg'),
  ];

  late _FakeRepository repository;
  late _FakeCovers covers;

  Future<_FakeHandler> pump(
    WidgetTester tester, {
    required Widget page,
    List<Track> tracks = const [],
    List<Track> library = const [],
    Playlist? saved,
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handler = _FakeHandler();
    repository = _FakeRepository();
    covers = _FakeCovers();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          libraryRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(preferences),
          coverStoreProvider.overrideWithValue(covers),
          allTracksProvider.overrideWith((ref) => library),
          favoritesProvider.overrideWith((ref) => tracks),
          currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          groupTracksProvider.overrideWith((ref, key) => tracks),
          playlistTracksProvider.overrideWith((ref, id) => tracks),
          playlistsProvider.overrideWith((ref) => [saved ?? _playlist]),
        ],
        child: MaterialApp(
          theme: buildNocTheme(brightness, NocAccent.red),
          home: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return handler;
  }

  const albumPage = GroupScreen(group: TrackGroup.album, name: 'Skyline');
  final playlistPage = PlaylistScreen(playlist: _playlist);

  // The covers standing at the top of the page.
  Finder fan() => find.descendant(
    of: find.byKey(const ValueKey('collection-covers')),
    matching: find.byType(Artwork),
  );

  testWidgets('shows the name, how many tracks and how long they run', (
    tester,
  ) async {
    await pump(tester, page: albumPage, tracks: album);

    expect(find.text('Skyline'), findsOneWidget);
    // 3 + 62 + 3 + 3 minutes.
    expect(find.text('4 tracks · 1 h 11 min'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Four'), findsOneWidget);
  });

  testWidgets('counts a single track in the singular', (tester) async {
    await pump(tester, page: albumPage, tracks: [album.first]);

    expect(find.text('1 track · 3 min'), findsOneWidget);
  });

  testWidgets('Play starts the list in order', (tester) async {
    final handler = await pump(tester, page: albumPage, tracks: album);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(handler.calls, ['play One of 4', 'shuffle none']);
  });

  testWidgets('Shuffle starts the list shuffled', (tester) async {
    final handler = await pump(tester, page: albumPage, tracks: album);

    await tester.tap(find.text('Shuffle'));
    await tester.pumpAndSettle();

    expect(handler.calls, ['play One of 4', 'shuffle all']);
  });

  testWidgets('tapping a track plays the list from there', (tester) async {
    final handler = await pump(tester, page: albumPage, tracks: album);

    await tester.tap(find.text('Three'));

    expect(handler.calls, ['play Three of 4']);
  });

  testWidgets('fans out up to three different covers', (tester) async {
    await pump(tester, page: albumPage, tracks: album);
    expect(fan(), findsNWidgets(3));
    // The first track's cover is the one in front, drawn last and largest.
    final front = tester.widget<Artwork>(fan().last);
    expect(front.path, '/art/a.jpg');
    for (final cover in tester.widgetList<Artwork>(fan())) {
      expect(cover.size, lessThanOrEqualTo(front.size));
    }
  });

  testWidgets('a list with one cover shows just that one', (tester) async {
    await pump(tester, page: albumPage, tracks: [album[0], album[3]]);

    expect(fan(), findsOneWidget);
  });

  testWidgets('with two covers nothing leans out on one side alone', (
    tester,
  ) async {
    await pump(tester, page: albumPage, tracks: [album[0], album[1]]);

    expect(fan(), findsOneWidget);
    expect(tester.widget<Artwork>(fan()).path, '/art/a.jpg');
  });

  group('favourites', () {
    testWidgets('open as a page like an album', (tester) async {
      final handler = await pump(
        tester,
        page: const FavouritesScreen(),
        tracks: album,
      );

      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('4 tracks · 1 h 11 min'), findsOneWidget);
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect(handler.calls, ['play One of 4', 'shuffle all']);
    });

    testWidgets('take a cover the user picks, in front of the others', (
      tester,
    ) async {
      await pump(tester, page: const FavouritesScreen(), tracks: album);
      expect(tester.widget<Artwork>(fan().last).path, '/art/a.jpg');

      await tester.tap(find.byTooltip('Favourites options'));
      await tester.pumpAndSettle();
      // There is nothing to remove until a cover has been chosen.
      expect(find.text('Remove cover'), findsNothing);
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      expect(tester.widget<Artwork>(fan().last).path, '/covers/mine.jpg');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('favourites_cover'), '/covers/mine.jpg');

      await tester.tap(find.byTooltip('Favourites options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove cover'));
      await tester.pumpAndSettle();

      expect(tester.widget<Artwork>(fan().last).path, '/art/a.jpg');
      expect(preferences.getString('favourites_cover'), isNull);
      // The picture that was replaced is not left behind.
      expect(covers.discarded, [null, '/covers/mine.jpg']);
    });
  });

  group('a playlist', () {
    testWidgets('is given a cover from its menu', (tester) async {
      await pump(tester, page: playlistPage, tracks: album);

      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      expect(find.text('Remove cover'), findsNothing);
      await tester.tap(find.text('Change cover'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['cover 4 /covers/mine.jpg']);
    });

    testWidgets('shows its own cover in front and can drop it', (tester) async {
      await pump(
        tester,
        page: playlistPage,
        tracks: album,
        saved: Playlist(
          id: 4,
          name: 'Night drive',
          createdAt: DateTime(2026),
          trackCount: 4,
          coverPath: '/covers/old.jpg',
        ),
      );
      expect(tester.widget<Artwork>(fan().last).path, '/covers/old.jpg');

      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove cover'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['cover 4 null']);
      expect(covers.discarded, ['/covers/old.jpg']);
    });

    testWidgets('is filled by ticking tracks from the library', (tester) async {
      final library = [
        ...album,
        _track(5, 'Five'),
        _track(6, 'Six'),
        _track(7, 'Seven'),
      ];
      await pump(tester, page: playlistPage, tracks: album, library: library);

      await tester.tap(find.byTooltip('Playlist options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add tracks'));
      await tester.pumpAndSettle();

      // Nothing is ticked yet, and what it already holds says so.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.text('Added'), findsNWidgets(4));

      await tester.tap(find.text('Seven'));
      await tester.tap(find.text('Five'));
      // A track already in it cannot be ticked again.
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(find.text('Add 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'six');
      await tester.pump();
      expect(find.text('Five'), findsNothing);
      await tester.tap(find.text('Six'));
      await tester.pump();

      await tester.tap(find.text('Add 3'));
      await tester.pumpAndSettle();

      // In the order they were ticked.
      expect(repository.calls, ['add 4 [7, 5, 6]']);
    });

    testWidgets('offers to add tracks while it is empty', (tester) async {
      await pump(tester, page: playlistPage, library: album);

      await tester.tap(find.text('Add tracks'));
      await tester.pumpAndSettle();

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Added'), findsNothing);
    });
  });

  testWidgets('a playlist can be renamed or deleted from its menu', (
    tester,
  ) async {
    await pump(tester, page: playlistPage, tracks: album);
    expect(find.text('Night drive'), findsOneWidget);

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete playlist'), findsOneWidget);
  });

  testWidgets('an album has no menu of its own', (tester) async {
    await pump(tester, page: albumPage, tracks: album);

    expect(find.byTooltip('Playlist options'), findsNothing);
  });

  testWidgets('an empty playlist says so and offers nothing to play', (
    tester,
  ) async {
    await pump(tester, page: playlistPage);

    expect(find.text('This playlist is empty'), findsOneWidget);
    expect(find.text('0 tracks'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Shuffle'), findsNothing);
  });

  testWidgets('the back button leaves the page', (tester) async {
    await pump(
      tester,
      tracks: album,
      page: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => albumPage)),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Skyline'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Skyline'), findsNothing);
  });

  for (final (name, size, scale, brightness) in [
    ('a small phone', const Size(320, 568), 1.0, Brightness.dark),
    (
      'a small phone with large text',
      const Size(320, 568),
      2.0,
      Brightness.dark,
    ),
    ('a phone in landscape', const Size(844, 390), 1.0, Brightness.light),
    ('a tablet', const Size(800, 1200), 1.0, Brightness.light),
  ]) {
    testWidgets('lays out without overflow on $name', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(
        tester,
        page: playlistPage,
        tracks: album,
        size: size,
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Night drive'), findsOneWidget);
    });
  }
}
