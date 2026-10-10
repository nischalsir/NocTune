import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/app.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/core/widgets/wave_bars.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/startup/startup_prompts.dart';
import 'package:noctune/features/startup/update_service.dart';
import 'package:noctune/third_party/spotiflac/mornye_bottom_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _track(String title) => Track(
  id: title.hashCode,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: 'Artist',
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

class _FakeHandler extends Fake implements NocAudioHandler {
  int cleared = 0;

  @override
  Future<void> clearQueue() async => cleared++;
}

/// A scan controller that sits in a fixed state and records what was asked.
class _IdleScanController extends ScanController {
  _IdleScanController(this.initial);

  final ScanState initial;
  static int scans = 0;

  @override
  ScanState build() => initial;

  @override
  Future<void> scan() async => scans++;

  @override
  Future<void> refreshIfPermitted() async {}
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  List<Track> tracks = const [],
  List<PlayedTrack> playLog = const [],
  List<TrackGroupSummary> albums = const [],
  List<Track> favourites = const [],
  MediaItem? nowPlaying,
  ScanState scan = const ScanIdle(),
  bool firstLaunch = false,
  NocAudioHandler? handler,
  Track? currentTrack,
  bool playing = false,
  bool settle = true,
  String? updateManifest,
  Map<String, Object> preferences = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    if (!firstLaunch) 'welcome_seen': true,
    ...preferences,
  });
  final prefs = await SharedPreferences.getInstance();
  const installed = AppVersion(1, 0, 0, 1);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (handler != null) audioHandlerProvider.overrideWithValue(handler),
        deviceDecodesAtmosProvider.overrideWith((ref) => false),
        allTracksProvider.overrideWith((ref) => tracks),
        recentlyAddedProvider.overrideWith((ref) => tracks),
        recentlyPlayedProvider.overrideWith((ref) => const []),
        favoritesProvider.overrideWith((ref) => favourites),
        libraryStatsProvider.overrideWith(
          (ref) => LibraryStats(
            trackCount: tracks.length,
            albumCount: 0,
            artistCount: 1,
            totalDuration: const Duration(minutes: 3) * tracks.length,
          ),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState(playing: playing)),
        ),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(
            currentTrack == null
                ? nowPlaying
                : mediaItemFromTrack(currentTrack),
          ),
        ),
        currentTrackProvider.overrideWith((ref) => currentTrack),
        playbackPositionProvider.overrideWith(
          (ref) => Stream.value(Duration.zero),
        ),
        playbackErrorProvider.overrideWith((ref) => const Stream.empty()),
        scanControllerProvider.overrideWith(() => _IdleScanController(scan)),
        mostPlayedProvider.overrideWith((ref) => const []),
        playLogProvider.overrideWith((ref) => playLog),
        topTracksInDaysProvider.overrideWith((ref, days) => const []),
        topGroupsProvider.overrideWith((ref, group) => const []),
        recentAlbumsProvider.overrideWith((ref) => albums),
        searchResultsProvider.overrideWith(
          (ref, query) => [
            for (final track in tracks)
              if (track.title.toLowerCase().contains(query.toLowerCase()))
                track,
          ],
        ),
        installedVersionProvider.overrideWith((ref) => installed),
        updateServiceProvider.overrideWith(
          (ref) => UpdateService(
            manifestUrl: updateManifest == null
                ? ''
                : 'https://example.com/update.json',
            installed: installed,
            preferences: prefs,
            isIos: false,
            fetch: (_) async => updateManifest!,
          ),
        ),
      ],
      child: const NocTuneApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // For screens with a continuous animation, which never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }
}

void main() {
  const phone = Size(390, 844);
  const tabletLandscape = Size(1280, 800);
  const desktop = Size(1600, 900);

  // The two round buttons the folded bar keeps: the current tab on the left
  // and the bar's last tab (Settings) on the right, whatever the key says.
  // They are always in the tree; folding is what makes them take taps.
  final foldedSearch = find
      .byKey(const ValueKey('mornye-compact-search'))
      .hitTestable();
  final foldedLeading = find
      .byKey(const ValueKey('mornye-compact-leading'))
      .hitTestable();

  testWidgets('phones get the floating glass bar with four tabs', (
    tester,
  ) async {
    await _pumpApp(tester, size: phone);

    expect(find.byType(MornyeBottomBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // Settings is reachable straight from the bar, in its last slot.
    final positions = [
      for (final label in ['Home', 'Library', 'Search', 'Settings'])
        tester.getCenter(find.text(label).last).dx,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(positions.toSet(), hasLength(4));
  });

  testWidgets('tablets keep the bottom bar in both orientations', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(800, 1200));
    expect(find.byType(MornyeBottomBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await _pumpApp(tester, size: tabletLandscape);
    expect(find.byType(MornyeBottomBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('desktop-width windows get a navigation rail', (tester) async {
    await _pumpApp(tester, size: desktop);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(MornyeBottomBar), findsNothing);
  });

  group('bottom bar', () {
    final many = [for (var i = 0; i < 40; i++) _track('Track $i')];

    testWidgets('folds its tabs away while a list is scrolled', (tester) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      expect(foldedSearch, findsNothing);

      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Folded: the two round side buttons replace the tabs.
      expect(foldedSearch, findsOneWidget);
      expect(foldedLeading, findsOneWidget);

      await tester.tap(foldedLeading);
      await tester.pumpAndSettle();
      expect(foldedSearch, findsNothing);
    });

    testWidgets('stays put when folding is switched off in Settings', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: phone,
        tracks: many,
        preferences: {'fold_navigation_on_scroll': false},
      );
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();

      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(foldedSearch, findsNothing);
    });

    testWidgets('the folded bar keeps Settings on its right', (tester) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Settings'), findsOneWidget);
      await tester.tap(foldedSearch);
      await tester.pumpAndSettle();

      expect(find.text('APPEARANCE').hitTestable(), findsOneWidget);
    });
    testWidgets('unfolds when the list is back at its top', (tester) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();

      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(foldedSearch, findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(foldedSearch, findsNothing);
    });

    testWidgets('back returns to Home, then asks before leaving', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone);
      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();
      expect(find.text('Search your library'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to NocTune'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('swiping the mini-player away clears the queue', (
      tester,
    ) async {
      final handler = _FakeHandler();
      await _pumpApp(
        tester,
        size: phone,
        handler: handler,
        nowPlaying: const MediaItem(id: 'file:///a.flac', title: 'Now Song'),
      );

      await tester.drag(find.text('Now Song'), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(handler.cleared, 1);
      expect(find.text('Now Song'), findsNothing);
    });
  });

  testWidgets('an empty library shows a welcome state', (tester) async {
    await _pumpApp(tester, size: phone);

    expect(find.text('Welcome to NocTune'), findsOneWidget);
  });

  testWidgets('an empty library on Android offers a device scan', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await _pumpApp(tester, size: phone);

    await tester.tap(find.text('Scan this device'));
    debugDefaultTargetPlatformOverride = null;

    expect(_IdleScanController.scans, 1);
    expect(find.text('Import files'), findsOneWidget);
  });

  testWidgets('an empty library on iOS offers import only', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _pumpApp(tester, size: phone);
    debugDefaultTargetPlatformOverride = null;

    expect(find.text('Scan this device'), findsNothing);
    expect(find.text('Import files'), findsOneWidget);
  });

  testWidgets('scan progress is shown with a way to cancel', (tester) async {
    await _pumpApp(tester, size: phone, scan: const ScanRunning(20, 300));

    expect(find.text('Reading tracks · 20 of 300'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('a denied permission explains itself and offers a retry', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: phone,
      scan: const ScanNeedsPermission(permanentlyDenied: false),
    );

    expect(find.textContaining('needs access to your music'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
  });

  testWidgets('home shows library totals and a switchable list', (
    tester,
  ) async {
    // Tall enough to show the hero, the totals and the list at once.
    await _pumpApp(
      tester,
      size: const Size(390, 1700),
      tracks: [_track('Aashish')],
    );

    // Nothing is loaded, so the hero offers the newest track.
    expect(find.text('NOCTUNE'), findsOneWidget);
    expect(find.text('RECENTLY ADDED'), findsOneWidget);
    expect(find.text('AASHISH'), findsOneWidget);
    expect(find.text('Play now'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Plays'), findsOneWidget);
    expect(find.text('Shuffle all'), findsOneWidget);
    // Nothing has been played yet, so the default list says so.
    expect(find.text('No tracks yet'), findsOneWidget);

    // The menu offers every way of looking at the listening history.
    await tester.tap(find.byTooltip('Choose what the list shows'));
    await tester.pumpAndSettle();
    for (final mode in [
      'Recent',
      'Most Played',
      'Last 7 Days',
      'Last 30 Days',
      'Top Artists',
      'Top Albums',
    ]) {
      expect(find.text(mode), findsWidgets, reason: mode);
    }
    await tester.tap(find.text('Top Artists').last);
    await tester.pumpAndSettle();
    expect(find.text('Top Artists'), findsOneWidget);

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('3:00'), findsOneWidget);
  });

  testWidgets('recent plays are grouped by day with repeat counts', (
    tester,
  ) async {
    final song = _track('Aashish');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await _pumpApp(
      tester,
      size: const Size(390, 1700),
      tracks: [song],
      playLog: [
        (track: song, playedAt: yesterday),
        (track: song, playedAt: yesterday.subtract(const Duration(minutes: 5))),
      ],
    );

    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Aashish'), findsOneWidget);
    expect(find.text('2\u00d7'), findsOneWidget);
  });

  testWidgets('Settings is a tab, and back returns from it to Home', (
    tester,
  ) async {
    await _pumpApp(tester, size: phone);
    final heading = find.text('APPEARANCE').hitTestable();
    expect(heading, findsNothing);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(heading, findsOneWidget);
    // The installed version and build number, not a placeholder.
    await tester.scrollUntilVisible(
      find.text('Version 1.0.0 (build 1)'),
      300,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(heading, findsNothing);
    expect(find.text('Welcome to NocTune').hitTestable(), findsOneWidget);
  });

  testWidgets('tabs keep their place when left and returned to', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: phone,
      tracks: [for (var i = 0; i < 40; i++) _track('Track $i')],
    );
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Track 3'), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Track 3').hitTestable(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mornye-compact-leading')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();

    // Still scrolled to where it was left.
    expect(find.text('Track 3').hitTestable(), findsNothing);
    expect(find.text('Track 20').hitTestable(), findsOneWidget);
  });

  group('hero', () {
    final loaded = _track('Sustari');

    testWidgets('shows moving bars and Now playing for the playing track', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: phone,
        tracks: [_track('Other'), loaded],
        currentTrack: loaded,
        playing: true,
        settle: false,
      );

      expect(find.text('NOW PLAYING'), findsOneWidget);
      expect(find.text('SUSTARI'), findsOneWidget);
      expect(find.text('Now playing'), findsOneWidget);
      expect(find.text('Play now'), findsNothing);
      // The hero's bars, and the ones on the track's row in the list.
      for (final bars in tester.widgetList<WaveBars>(find.byType(WaveBars))) {
        expect(bars.playing, isTrue);
      }
      // The bars keep moving, so this screen never comes to rest.
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('holds the bars still while paused', (tester) async {
      await _pumpApp(
        tester,
        size: phone,
        tracks: [loaded],
        currentTrack: loaded,
      );

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Paused'), findsWidgets);
      for (final bars in tester.widgetList<WaveBars>(find.byType(WaveBars))) {
        expect(bars.playing, isFalse);
      }
    });

    testWidgets('holds the bars still with reduced motion on', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await _pumpApp(
        tester,
        size: phone,
        tracks: [loaded],
        currentTrack: loaded,
        playing: true,
      );

      expect(find.text('Now playing'), findsOneWidget);
    });
  });

  testWidgets('the mini-player is hidden while nothing is loaded', (
    tester,
  ) async {
    await _pumpApp(tester, size: phone);

    expect(find.byTooltip('Next'), findsNothing);
  });

  testWidgets('the mini-player shows the loaded track', (tester) async {
    await _pumpApp(
      tester,
      size: phone,
      nowPlaying: const MediaItem(id: 'file:///a.flac', title: 'Now Song'),
    );
    expect(find.text('Now Song'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  group('startup popups', () {
    const manifest =
        '{"version": "1.2.0", "url": "https://example.com/release", '
        '"notes": ["Synchronised lyrics"]}';

    testWidgets('a first launch is welcomed, and only once', (tester) async {
      await _pumpApp(tester, size: phone, firstLaunch: true);

      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('Get started'), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('welcome_seen'), isTrue);
    });

    testWidgets('an ordinary launch shows no popup', (tester) async {
      await _pumpApp(tester, size: phone);

      expect(find.text('Get started'), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('a newer release is announced with both versions', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, updateManifest: manifest);

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('1.2.0'), findsOneWidget);
      expect(find.text('Synchronised lyrics'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('the update waits for the welcome to be dismissed', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: phone,
        firstLaunch: true,
        updateManifest: manifest,
      );

      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Update available'), findsNothing);

      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();

      expect(find.text('Get started'), findsNothing);
      expect(find.text('Update available'), findsOneWidget);
    });

    testWidgets('a required update offers only the update', (tester) async {
      await _pumpApp(
        tester,
        size: phone,
        updateManifest:
            '{"version": "2.0.0", "url": "https://example.com/r", '
            '"mandatory": true}',
      );

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsNothing);

      // Tapping outside must not dismiss it.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Update required'), findsOneWidget);
    });
  });

  testWidgets('navigates between destinations', (tester) async {
    await _pumpApp(tester, size: phone);

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('Tracks'), findsWidgets);

    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.text('Search your library'), findsOneWidget);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to NocTune'), findsOneWidget);
  });

  testWidgets('the layout survives large text on a small phone', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpApp(
      tester,
      size: const Size(320, 568),
      tracks: [_track('A very long track title that should be truncated')],
    );

    expect(tester.takeException(), isNull);
  });

  group('home', () {
    final songs = [_track('Aashish'), _track('Balenci'), _track('Sustari')];

    testWidgets('typing in the search field shows results on Home itself', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, tracks: songs);

      await tester.enterText(find.byType(TextField).first, 'bal');
      await tester.pumpAndSettle();

      // Still on Home: the results take the place of the feed.
      expect(find.text('Balenci'), findsOneWidget);
      expect(find.text('Aashish'), findsNothing);
      expect(find.text('NOCTUNE'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('NOCTUNE'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '',
      );
    });

    testWidgets('back closes a search before anything else', (tester) async {
      await _pumpApp(tester, size: phone, tracks: songs);
      await tester.enterText(find.byType(TextField).first, 'sus');
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('NOCTUNE'), findsOneWidget);
      expect(find.text('Press back again to exit'), findsNothing);
    });

    testWidgets('says so when the search matches nothing', (tester) async {
      await _pumpApp(tester, size: phone, tracks: songs);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('shows shelves of the newest albums and the favourites', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: const Size(390, 1700),
        tracks: songs,
        albums: const [
          TrackGroupSummary(name: 'P-POP CULTURE', trackCount: 9, artist: 'KA'),
        ],
        favourites: [songs[1]],
      );

      expect(find.text('Albums'), findsWidgets);
      expect(find.text('P-POP CULTURE'), findsOneWidget);
      expect(find.text('Favourites'), findsOneWidget);
      // The shelves come before the play statistics.
      expect(
        tester.getTopLeft(find.text('Favourites')).dy,
        lessThan(tester.getTopLeft(find.text('Plays')).dy),
      );
    });

    testWidgets('has no shelves when there is nothing to put on them', (
      tester,
    ) async {
      await _pumpApp(tester, size: const Size(390, 1700), tracks: songs);

      expect(find.text('Favourites'), findsNothing);
      expect(find.text('See all'), findsNothing);
    });
  });

  testWidgets('the Search page opens with the keyboard up', (tester) async {
    await _pumpApp(tester, size: phone);
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isTrue);
  });
}
