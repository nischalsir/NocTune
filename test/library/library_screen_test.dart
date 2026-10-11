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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(repository),
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

  testWidgets('explains sections that have nothing in them', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Favourites'));
    await settle(tester);
    expect(find.text('No favourites yet'), findsOneWidget);

    await tester.tap(find.text('Genres'));
    await settle(tester);
    expect(find.text('None of your tracks has a genre tag.'), findsOneWidget);
  });

  testWidgets('the track menu queues and favourites a track', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('More for One'));
    await settle(tester);
    await tester.tap(find.text('Play next'));
    await settle(tester);
    expect(handler.calls, ['next One']);

    await tester.tap(find.byTooltip('More for One'));
    await settle(tester);
    await tester.tap(find.text('Add to favourites'));
    await settle(tester);

    await tester.tap(find.text('Favourites'));
    await settle(tester);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('creates a playlist and adds a track to it', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('More for Three'));
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
}
