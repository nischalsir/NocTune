// Renders the main screens to PNG files so their layout can be reviewed
// without a device. Uses fixed sample data, never the real library.
//
//     flutter test tool/preview_screens.dart --dart-define=OUT=<folder>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/app.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/equalizer/equalizer_controller.dart';
import 'package:noctune/features/equalizer/equalizer_settings.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/lyrics/lyrics.dart';
import 'package:noctune/features/lyrics/lyrics_source.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/playback/now_playing_route.dart';
import 'package:noctune/features/playback/now_playing_screen.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/settings/settings_screen.dart';
import 'package:noctune/features/startup/startup_prompts.dart';
import 'package:noctune/features/startup/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = String.fromEnvironment('OUT');
// The fonts Flutter ships for Material apps; `flutter test` sets FLUTTER_ROOT.
final _fonts =
    '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';

// The playlist page asks for the repository; the previews never write to it.
class _NoRepository extends Fake implements LibraryRepository {}

/// Takes the equaliser's settings and does nothing with them.
class _SilentHandler extends Fake implements NocAudioHandler {
  @override
  Future<void> applyEqualizer(EqualizerSettings settings) async {}
}

class _IdleScan extends ScanController {
  @override
  ScanState build() => const ScanIdle();

  @override
  Future<void> refreshIfPermitted() async {}
}

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(
      File('$_fonts/Roboto-$name.ttf').readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File('$_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  await icons.load();
  // The app's own typefaces and the icon font of the navigation bar, read
  // from the asset bundle the test runner builds.
  for (final (family, asset) in const [
    ('Google Sans Flex', 'assets/fonts/GoogleSansFlex.ttf'),
    ('Inter', 'assets/fonts/InterVariable.ttf'),
    (
      'packages/cupertino_icons/CupertinoIcons',
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
}

Future<String> _cover(String name, Color a, Color b) async {
  final recorder = ui.PictureRecorder();
  const rect = Rect.fromLTWH(0, 0, 400, 400);
  Canvas(recorder)
    ..drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a, b],
        ).createShader(rect),
    )
    ..drawCircle(const Offset(280, 140), 70, Paint()..color = Colors.white24);
  final image = await recorder.endRecording().toImage(400, 400);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$_out/cover_$name.png')
    ..writeAsBytesSync(png!.buffer.asUint8List());
  return file.path;
}

void main() {
  testWidgets('render previews', (tester) async {
    Directory(_out).createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final covers = (await tester.runAsync(
      () async => [
        await _cover('a', const Color(0xFF3A6EA5), const Color(0xFF101C33)),
        await _cover('b', const Color(0xFFB8442F), const Color(0xFF2A0F14)),
        await _cover('c', const Color(0xFF5E8C61), const Color(0xFF142018)),
      ],
    ))!;

    Track track(int id, String title, String artist, String codec, int plays) =>
        Track(
          id: id,
          uri: '/music/$title.flac',
          fileName: '$title.flac',
          folder: '/music',
          title: title,
          artist: artist,
          album: 'Midnight Sessions',
          duration: const Duration(minutes: 4, seconds: 12),
          codec: codec,
          sampleRate: 96000,
          bitDepth: 24,
          artPath: covers[id % covers.length],
          playCount: plays,
          dateAdded: DateTime(2026),
          dateModified: DateTime(2026),
        );
    final tracks = [
      track(1, 'Northern Lights', 'Aurora Vale', 'flac', 12),
      track(2, 'Paper Lanterns', 'The Quiet Hours', 'aac', 9),
      track(3, 'Low Tide', 'Marlowe', 'flac', 7),
      track(4, 'Glass Garden', 'Aurora Vale', 'eac3-joc', 5),
      track(5, 'Slow Train Home', 'Marlowe', 'flac', 3),
      track(6, 'After the Rain', 'The Quiet Hours', 'flac', 2),
      track(7, 'Harbour Lights', 'Marlowe', 'flac', 1),
    ];

    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'welcome_seen': true,
      // --dart-define=THEME=light renders the light theme instead.
      'theme_mode': const String.fromEnvironment('THEME', defaultValue: 'dark'),
    });
    final preferences = await SharedPreferences.getInstance();
    const installed = AppVersion(1, 0, 0, 1);

    Future<void> shoot(
      String name, {
      required Widget child,
      required Track playing,
      bool atmos = false,
      // The lyrics' clock, for a shot that moves it by hand.
      Stream<Duration>? lyricsPosition,
      Future<void> Function()? act,
      // False to capture the frame [act] leaves, e.g. part-way through an
      // animation, instead of letting things come to rest first.
      bool settleAfterAct = true,
    }) async {
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            libraryRepositoryProvider.overrideWithValue(_NoRepository()),
            audioHandlerProvider.overrideWithValue(_SilentHandler()),
            equalizerBandsProvider.overrideWith(
              (ref) => (
                minDb: -15.0,
                maxDb: 15.0,
                centers: [60.0, 230.0, 910.0, 3600.0, 14000.0],
              ),
            ),
            playlistsProvider.overrideWith(
              (ref) => [
                Playlist(
                  id: 1,
                  name: 'Night drive',
                  createdAt: DateTime(2026),
                  trackCount: tracks.length,
                ),
              ],
            ),
            playlistTracksProvider.overrideWith((ref, id) => tracks),
            searchResultsProvider.overrideWith(
              (ref, query) => [
                for (final track in tracks)
                  if (track.title.toLowerCase().contains(query.toLowerCase()))
                    track,
              ],
            ),
            allTracksProvider.overrideWith((ref) => tracks),
            recentlyAddedProvider.overrideWith((ref) => tracks),
            recentlyPlayedProvider.overrideWith((ref) => tracks),
            mostPlayedProvider.overrideWith((ref) => tracks),
            playLogProvider.overrideWith((ref) {
              final now = DateTime.now();
              DateTime ago(int days, int minutes) =>
                  now.subtract(Duration(days: days, minutes: minutes));
              return [
                (track: tracks[0], playedAt: ago(0, 1)),
                (track: tracks[2], playedAt: ago(0, 20)),
                (track: tracks[1], playedAt: ago(0, 45)),
                (track: tracks[2], playedAt: ago(0, 70)),
                (track: tracks[4], playedAt: ago(1, 10)),
                (track: tracks[4], playedAt: ago(1, 30)),
                (track: tracks[4], playedAt: ago(1, 50)),
                (track: tracks[5], playedAt: ago(1, 90)),
                (track: tracks[6], playedAt: ago(6, 0)),
              ];
            }),
            topTracksInDaysProvider.overrideWith(
              (ref, days) => [
                for (final t in tracks) (track: t, plays: t.playCount),
              ],
            ),
            topGroupsProvider.overrideWith((ref, group) => const []),
            favoritesProvider.overrideWith(
              (ref) => [tracks[2], tracks[0], tracks[4], tracks[5]],
            ),
            recentAlbumsProvider.overrideWith(
              (ref) => [
                for (final (index, name) in const [
                  'Midnight Sessions',
                  'Tidewater',
                  'Paper Lanterns',
                  'Glasshouse',
                ].indexed)
                  TrackGroupSummary(
                    name: name,
                    trackCount: 9,
                    artPath: covers[index % covers.length],
                    artist: tracks[index].artist,
                  ),
              ],
            ),
            libraryStatsProvider.overrideWith(
              (ref) => const LibraryStats(
                trackCount: 319,
                albumCount: 96,
                artistCount: 142,
                totalDuration: Duration(hours: 21, minutes: 14),
                playCount: 1284,
                listenedDuration: Duration(hours: 86, minutes: 21),
              ),
            ),
            currentTrackProvider.overrideWith((ref) => playing),
            deviceDecodesAtmosProvider.overrideWith((ref) => atmos),
            lyricsProvider.overrideWith(
              (ref, key) => LoadedLyrics(
                parseLyrics(
                  '[00:05.00]The harbour sleeps beneath the rain\n'
                  '[00:20.00]And every window holds a flame\n'
                  '[00:40.00]I count the lights along the shore\n'
                  '[01:00.00]And wonder who they\'re burning for\n'
                  '[01:20.00]\n'
                  '[01:30.00]Northern lights, carry me home\n'
                  '[01:50.00]Over the water, over the stone\n',
                )!,
                LyricsOrigin.embedded,
              ),
            ),
            playbackStateProvider.overrideWith(
              (ref) => Stream.value(PlaybackState(playing: true)),
            ),
            currentMediaItemProvider.overrideWith(
              (ref) => Stream.value(mediaItemFromTrack(playing)),
            ),
            unsavedListeningProvider.overrideWithValue(Duration.zero),
            playbackPositionProvider.overrideWith(
              (ref) => Stream.value(const Duration(seconds: 63)),
            ),
            lyricsPositionProvider.overrideWith(
              (ref) =>
                  lyricsPosition ?? Stream.value(const Duration(seconds: 63)),
            ),
            playbackErrorProvider.overrideWith((ref) => const Stream.empty()),
            queueProvider.overrideWith((ref) => Stream.value(const [])),
            scanControllerProvider.overrideWith(_IdleScan.new),
            installedVersionProvider.overrideWith((ref) => installed),
            updateServiceProvider.overrideWith(
              (ref) => UpdateService(
                manifestUrl: '',
                installed: installed,
                preferences: preferences,
                isIos: false,
              ),
            ),
          ],
          child: RepaintBoundary(key: key, child: child),
        ),
      );
      // Let file images load and decode, which needs real time.
      for (var i = 0; i < 14; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
      if (act != null) {
        await act();
        for (var i = 0; settleAfterAct && i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File('$_out/$name.png').writeAsBytesSync(bytes!);
    }

    Widget player() => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNocTheme(Brightness.dark, NocAccent.red),
      home: const Scaffold(body: NowPlayingScreen()),
    );

    await shoot('1_home', child: const NocTuneApp(), playing: tracks[0]);
    await shoot(
      '2_home_scrolled',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () => tester.dragFrom(const Offset(195, 560), const Offset(0, -470)),
    );
    // Scrolled to the end: the List card's table, with the bar folded away.
    await shoot(
      '2b_home_list',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () => tester.dragFrom(const Offset(195, 560), const Offset(0, -2400)),
    );
    // The bar part-way through folding, to check the shape it takes.
    for (final (name, elapsed) in const [
      ('8_fold_early', 170),
      ('9_fold_late', 330),
    ]) {
      await shoot(
        name,
        child: const NocTuneApp(),
        playing: tracks[0],
        settleAfterAct: false,
        act: () async {
          await tester.dragFrom(const Offset(195, 560), const Offset(0, -470));
          await tester.pump();
          await tester.pump(Duration(milliseconds: elapsed));
        },
      );
    }
    // The bar with a finger held on a tab: the glass selector is up and the
    // flat pill has made way for it. Only a renderer with shader filters
    // draws the glass, so run with --enable-impeller to see it.
    TestGesture? finger;
    await shoot(
      '10_bar_pressed',
      child: const NocTuneApp(),
      playing: tracks[0],
      settleAfterAct: false,
      act: () async {
        finger = await tester.startGesture(
          tester.getCenter(find.text('Library').last),
        );
        await tester.pump();
        // The lens moves on a ticker, so it needs its frames one by one.
        for (var i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      },
    );
    await finger?.up();
    await tester.pump();
    await shoot('3_player_lossless', child: player(), playing: tracks[0]);
    await shoot(
      '4_player_atmos',
      child: player(),
      playing: tracks[3],
      atmos: true,
    );
    await shoot(
      '5_player_lyrics',
      child: player(),
      playing: tracks[0],
      act: () => tester.tap(find.byTooltip('Show lyrics')),
    );
    // The lyrics a moment into a line change, to check that the lines
    // changing size are drawn right while they are scaled as pictures.
    final clock = StreamController<Duration>.broadcast();
    await shoot(
      '11_lyrics_changing',
      child: player(),
      playing: tracks[0],
      lyricsPosition: clock.stream,
      settleAfterAct: false,
      act: () async {
        await tester.tap(find.byTooltip('Show lyrics'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        clock.add(const Duration(seconds: 41));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        clock.add(const Duration(seconds: 61));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 150));
      },
    );
    await clock.close();
    await shoot(
      '6_settings',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () => tester.tap(find.text('Settings').last),
    );
    await shoot(
      '7_settings_about',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () async {
        await tester.tap(find.text('Settings').last);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -2400));
      },
    );
    // A playlist's page, reached the way it is on the phone.
    Future<void> openPlaylist() async {
      await tester.tap(find.text('Library').last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Playlists'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Night drive'));
      // The page's covers are decoded at a new size, which needs real time.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await shoot(
      '12_playlist',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: openPlaylist,
    );
    await shoot(
      '13_playlist_scrolled',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () async {
        await openPlaylist();
        await tester.dragFrom(const Offset(195, 600), const Offset(0, -330));
      },
    );
    // The library tab, its search, and the favourites page.
    Future<void> settleCovers() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await shoot(
      '17_library',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () => tester.tap(find.text('Library').last, warnIfMissed: false),
    );
    await shoot(
      '18_library_search',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () async {
        await tester.tap(find.text('Library').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byTooltip('Search the library'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField).last, 'li');
      },
    );
    await shoot(
      '19_favourites',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () async {
        await tester.tap(find.text('Library').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 600));
        // Its chip is past the edge of a phone until the row is scrolled.
        await tester.ensureVisible(find.text('Favourites').last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Favourites').last);
        await settleCovers();
      },
    );
    // The player part-way through growing out of the mini-player, to check
    // the shape it takes and where the tabs are while it does.
    for (final (name, elapsed) in const [
      ('14_player_opening_60', 60),
      ('15_player_opening_150', 150),
      ('16_player_opening_240', 240),
    ]) {
      await shoot(
        name,
        child: const NocTuneApp(),
        playing: tracks[0],
        settleAfterAct: false,
        act: () async {
          await tester.tap(find.byKey(miniPlayerSurfaceKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(Duration(milliseconds: elapsed - 16));
        },
      );
    }
    // Last, because it leaves the equaliser switched on in the preferences.
    await shoot(
      '20_equaliser',
      child: const NocTuneApp(),
      playing: tracks[0],
      act: () async {
        await tester.tap(find.text('Settings').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.dragUntilVisible(
          find.text('Equaliser'),
          find.byType(SettingsScreen),
          const Offset(0, -250),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Equaliser'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byType(CupertinoSwitch).last);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('Rock'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Rock'));
      },
    );
    tester.view.reset();
  });
}
