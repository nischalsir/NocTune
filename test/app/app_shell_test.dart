import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:noctune/app/app.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/widgets/wave_bars.dart';
import 'package:noctune/features/home/home_hero.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/playback/now_playing_route.dart';
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
        groupTracksProvider.overrideWith((ref, key) => tracks),
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

    testWidgets('parts and closes in step with the mini-player above it', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();

      // The cut that parts the tab row in the middle, and the box that
      // gives up the row's height so the mini-player can come down.
      final cut = find.descendant(
        of: find.byType(MornyeBottomBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ClipPath &&
              widget.clipper.runtimeType.toString() == '_FoldClipper',
          skipOffstage: false,
        ),
        skipOffstage: false,
      );
      final row = find.ancestor(
        of: cut,
        matching: find.byWidgetPredicate(
          (widget) => widget is Align && widget.heightFactor != null,
          skipOffstage: false,
        ),
      );
      // How far the mini-player has come down, from 0 to 1.
      double lowered() => 1 - tester.widget<Align>(row.first).heightFactor!;
      // How far the halves have drawn back to the sides, from 0 to 1, read
      // from where the left half ends.
      double parted() {
        final size = tester.getSize(cut);
        final shape = tester.widget<ClipPath>(cut).clipper!.getClip(size);
        var edge = size.width / 2;
        while (edge > 0 &&
            !shape.contains(Offset(edge - 0.25, size.height - 30))) {
          edge -= 0.25;
        }
        return (size.width / 2 - edge) / (size.width / 2 - 52);
      }

      Future<int> watch() async {
        var midway = 0;
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final down = lowered();
          if (down < 0.03 || down > 0.97) continue;
          midway++;
          expect(parted(), closeTo(down, 0.02));
        }
        return midway;
      }

      // Scrolling down: the bar parts as the mini-player comes down.
      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      expect(await watch(), greaterThan(8));
      await tester.pumpAndSettle();
      expect(lowered(), 1);

      // And back: it fills in from the sides as the mini-player rises.
      await tester.tap(foldedLeading);
      expect(await watch(), greaterThan(8));
      await tester.pumpAndSettle();
      expect(lowered(), 0);
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

    testWidgets('on glass its tabs are the glass tab bar, with one pill', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone);

      final tabs = tester.widget<LiquidGlassTabBar>(
        find.byType(LiquidGlassTabBar),
      );
      expect(tabs.items.map((item) => item.label), [
        'Home',
        'Library',
        'Search',
        'Settings',
      ]);
      // The selection travels as a lens where the renderer can draw one.
      expect(tabs.pillStyle.mode, LiquidGlassPillMode.impellerOnly);
      expect(tabs.pillStyle.animated, isTrue);

      await tester.tap(find.text('Library').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LiquidGlassTabBar>(find.byType(LiquidGlassTabBar))
            .selectedIndex,
        1,
      );
    });

    testWidgets('the active tab takes the accent, not a colour of its own', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, preferences: {'accent': 'blue'});

      expect(
        tester
            .widget<LiquidGlassTabBar>(find.byType(LiquidGlassTabBar))
            .itemStyle
            .selectedColor,
        NocAccent.blue.onDark,
      );
    });

    testWidgets('with reduced motion its tabs are the flat bar', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpApp(tester, size: phone);

      expect(find.byType(LiquidGlassTabBar), findsNothing);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      expect(find.text('Tracks'), findsWidgets);
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

  group('opening the player', () {
    const song = MediaItem(id: 'file:///a.flac', title: 'Now Song');
    const frame = Duration(milliseconds: 16);

    // The surface the player is showing through, in screen coordinates.
    // A new page is kept offstage for its first frame, which still counts.
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is ClipRRect &&
          widget.clipper.runtimeType.toString() == '_SurfaceClipper',
      skipOffstage: false,
    );
    Rect shown(WidgetTester tester) =>
        tester.widget<ClipRRect>(surface).clipper!.getClip(Size.zero).outerRect;

    testWidgets('it grows out of the mini-player and pushes the tabs down', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, nowPlaying: song);
      final mini = tester.getRect(find.byKey(miniPlayerSurfaceKey));
      final tabs = tester.getTopLeft(find.text('Home').last).dy;
      expect(playerBarPush.value, 0);

      await tester.tap(find.text('Now Song'));
      await tester.pump();
      // It starts as the mini-player's own shape, in the same place, with
      // the tabs where they were.
      expect(shown(tester), mini);
      expect(playerBarPush.value, 0);

      var before = mini;
      var largestStep = 0.0;
      var midway = 0;
      for (var i = 0; i < 40; i++) {
        await tester.pump(frame);
        final now = shown(tester);
        // Its top goes up and its bottom goes down, and neither comes back.
        expect(now.top, lessThanOrEqualTo(before.top));
        expect(now.bottom, greaterThanOrEqualTo(before.bottom));
        largestStep = [
          largestStep,
          before.top - now.top,
          now.bottom - before.bottom,
        ].reduce((a, b) => a > b ? a : b);
        // The tabs stay just under its lower edge.
        expect(playerBarPush.value, closeTo(now.bottom - mini.bottom, 0.01));
        if (now.bottom < phone.height - 1) {
          midway++;
          expect(
            tester.getTopLeft(find.text('Home').last).dy,
            closeTo(tabs + playerBarPush.value, 0.01),
          );
        }
        before = now;
      }
      await tester.pumpAndSettle();

      expect(midway, greaterThan(8));
      // No part of it crosses the screen in a single frame.
      expect(largestStep, lessThan(80));
      expect(shown(tester), Offset.zero & phone);
      expect(playerBarPush.value, closeTo(phone.height - mini.bottom, 0.01));
      expect(find.text('NOW PLAYING'), findsOneWidget);
    });

    testWidgets('closing it shrinks back into the mini-player', (tester) async {
      await _pumpApp(tester, size: phone, nowPlaying: song);
      final mini = tester.getRect(find.byKey(miniPlayerSurfaceKey));
      await tester.tap(find.text('Now Song'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close player'));
      await tester.pump();
      var before = shown(tester);
      for (var i = 0; i < 30 && surface.evaluate().isNotEmpty; i++) {
        await tester.pump(frame);
        if (surface.evaluate().isEmpty) break;
        final now = shown(tester);
        expect(now.top, greaterThanOrEqualTo(before.top));
        expect(now.bottom, lessThanOrEqualTo(before.bottom));
        before = now;
      }
      await tester.pumpAndSettle();

      // It ended on the mini-player, and the tabs are back where they were.
      expect(before.top, closeTo(mini.top, 12));
      expect(playerBarPush.value, 0);
      expect(find.text('NOW PLAYING'), findsNothing);
      expect(find.text('Now Song'), findsOneWidget);
    });

    testWidgets('dragging it down closes it, and the tabs come back with it', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone, nowPlaying: song);
      await tester.tap(find.text('Now Song'));
      await tester.pumpAndSettle();
      final pushed = playerBarPush.value;

      // On the cover, which leaves vertical drags to the page.
      final finger = await tester.startGesture(const Offset(195, 300));
      await finger.moveBy(const Offset(0, 40));
      await tester.pump();
      await finger.moveBy(const Offset(0, 300));
      await tester.pump();

      // Under the finger it is part-way shut, with the tabs part-way back.
      expect(shown(tester).top, greaterThan(0));
      expect(playerBarPush.value, inExclusiveRange(0, pushed));

      await finger.up();
      await tester.pumpAndSettle();
      expect(playerBarPush.value, 0);
      expect(find.text('NOW PLAYING'), findsNothing);
    });

    testWidgets('with reduced motion it fades in and nothing moves', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pumpApp(tester, size: phone, nowPlaying: song);

      await tester.tap(find.text('Now Song'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(surface, findsNothing);
      expect(playerBarPush.value, 0);
      await tester.pumpAndSettle();
      expect(find.text('NOW PLAYING'), findsOneWidget);
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
    // Noon, so that five minutes earlier is the same day whatever the time
    // the test runs at.
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
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

    testWidgets('blurs nothing behind its glass while its bars move', (
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

      // The bars redraw the screen on every frame while music plays. A blur
      // of what is behind each pill, worked out again on each of those
      // frames, is what took the phone's whole frame time.
      expect(find.text('Now playing'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HomeHero),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
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

    testWidgets('an album opened from Home keeps the bar and mini-player', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        size: const Size(390, 1700),
        tracks: songs,
        albums: const [
          TrackGroupSummary(name: 'P-POP CULTURE', trackCount: 3, artist: 'KA'),
        ],
        nowPlaying: const MediaItem(id: 'file:///a.flac', title: 'Now Song'),
      );

      await tester.tap(find.text('P-POP CULTURE'));
      await tester.pumpAndSettle();

      // Its page, with the navigation still on screen and usable.
      expect(find.text('3 tracks · 9 min'), findsOneWidget);
      expect(find.byType(MornyeBottomBar), findsOneWidget);
      expect(find.text('Now Song').hitTestable(), findsOneWidget);

      // Back leaves the page before it does anything else.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('3 tracks · 9 min'), findsNothing);
      expect(find.text('Albums'), findsWidgets);
      expect(find.text('Press back again to exit'), findsNothing);
    });

    testWidgets('See all on the favourites opens their page', (tester) async {
      await _pumpApp(
        tester,
        size: const Size(390, 1700),
        tracks: songs,
        favourites: [songs[1]],
      );

      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();

      expect(find.text('1 track · 3 min'), findsOneWidget);
      expect(find.byTooltip('Favourites options'), findsOneWidget);
      expect(find.byType(MornyeBottomBar), findsOneWidget);
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
