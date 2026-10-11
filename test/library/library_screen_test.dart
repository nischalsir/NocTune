import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/library_screen.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final calls = <String>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async =>
      calls.add('play ${tracks[initialIndex].title} of ${tracks.length}');

  @override
  Future<void> playNext(Track track) async => calls.add('next ${track.title}');

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async =>
      calls.add('queue ${mediaItem.title}');
}

class _IdleScanController extends ScanController {
  @override
  ScanState build() => const ScanIdle();
}

void main() {
  late Database db;
  late LibraryRepository repository;
  late _FakeHandler handler;

  setUpAll(sqfliteFfiInit);

  // The database does real IO, which only makes progress outside the fake
  // clock that widget tests run under.
  Future<void> settle(WidgetTester tester) async {
    // Fixed pumps rather than pumpAndSettle, which never settles while a
    // loading spinner is animating.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    // Wide enough that every section chip is on screen without scrolling.
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      repository = LibraryRepository(db);
      await repository.upsertTracks([
        for (final (title, artist, album) in [
          ('One', 'Aurora', 'Skyline'),
          ('Two', 'Aurora', 'Skyline'),
          ('Three', 'Nova', 'Horizon'),
        ])
          Track(
            uri: '/music/$title.flac',
            fileName: '$title.flac',
            folder: '/music',
            title: title,
            artist: artist,
            album: album,
            duration: const Duration(minutes: 3),
            dateAdded: DateTime(2026),
            dateModified: DateTime(2026),
          ),
      ]);
    });
    addTearDown(() => tester.runAsync(db.close));
    handler = _FakeHandler();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(preferences),
          audioHandlerProvider.overrideWithValue(handler),
          currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          scanControllerProvider.overrideWith(_IdleScanController.new),
        ],
        child: MaterialApp(
          theme: buildNocTheme(Brightness.dark, NocAccent.red),
          home: const Scaffold(body: LibraryScreen()),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('lists tracks and plays the list from the tapped one', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Two'));

    expect(handler.calls, ['play Two of 3']);
  });

  testWidgets('browses albums and opens one', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Albums'));
    await settle(tester);
    expect(find.text('Aurora · 2 tracks'), findsOneWidget);

    await tester.tap(find.text('Skyline'));
    await settle(tester);

    expect(find.text('2 tracks · 6 min'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Three'), findsNothing);
  });

  testWidgets('the round button on a row plays the list from that track', (
    tester,
  ) async {
    await pump(tester);

    final row = find.ancestor(
      of: find.text('Three'),
      matching: find.byType(InkWell),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.play_arrow_rounded)),
    );

    expect(handler.calls, ['play Three of 3']);
  });

  testWidgets('has a search of its own, with results in place', (tester) async {
    await pump(tester);
    expect(find.text('Your library'), findsOneWidget);

    await tester.tap(find.byTooltip('Search the library'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'thr');
    await settle(tester);

    // The results take the place of the list, and of the chips.
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('One'), findsNothing);
    expect(find.text('Albums'), findsNothing);
    await tester.tap(find.text('Three'));
    expect(handler.calls, ['play Three of 1']);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Your library'), findsOneWidget);
  });

  testWidgets('back closes its search before anything else', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Search the library'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('No matches'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.text('No matches'), findsNothing);
    expect(find.text('Your library'), findsOneWidget);
  });

  testWidgets('explains sections that have nothing in them', (tester) async {
    await pump(tester);

    // The favourites open as a page of their own.
    await tester.tap(find.text('Favourites'));
    await settle(tester);
    expect(find.text('No favourites yet'), findsOneWidget);
    expect(find.text('0 tracks'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    await tester.tap(find.text('Genres'));
    await settle(tester);
    expect(find.text('None of your tracks has a genre tag.'), findsOneWidget);
  });

  testWidgets('the track menu queues and favourites a track', (tester) async {
    await pump(tester);

    // The menu is a press and hold away.
    await tester.longPress(find.text('One'));
    await settle(tester);
    await tester.tap(find.text('Play next'));
    await settle(tester);
    expect(handler.calls, ['next One']);

    await tester.longPress(find.text('One'));
    await settle(tester);
    await tester.tap(find.text('Add to favourites'));
    await settle(tester);

    await tester.tap(find.text('Favourites'));
    await settle(tester);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
    expect(find.text('1 track · 3 min'), findsOneWidget);
  });

  testWidgets('creates a playlist and adds a track to it', (tester) async {
    await pump(tester);

    await tester.longPress(find.text('Three'));
    await settle(tester);
    await tester.tap(find.text('Add to playlist…'));
    await settle(tester);
    await tester.tap(find.text('New playlist'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Night drive');
    await tester.tap(find.text('Create'));
    await settle(tester);

    await tester.tap(find.text('Playlists'));
    await settle(tester);
    expect(find.text('Night drive'), findsOneWidget);
    expect(find.text('1 track'), findsOneWidget);

    await tester.tap(find.text('Night drive'));
    await settle(tester);
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets('a playlist made in the library opens straight away', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Playlists'));
    await settle(tester);

    await tester.tap(find.text('New playlist'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.text('Create'));
    await settle(tester);

    // Its own page, empty, with the way to fill it.
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('This playlist is empty'), findsOneWidget);
    expect(find.text('Add tracks'), findsOneWidget);
  });
}
