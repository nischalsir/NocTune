import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/app.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/app/noc_bottom_bar.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/startup/startup_prompts.dart';
import 'package:noctune/features/startup/update_service.dart';
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
  MediaItem? nowPlaying,
  ScanState scan = const ScanIdle(),
  bool firstLaunch = false,
  NocAudioHandler? handler,
  String? updateManifest,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    if (!firstLaunch) 'welcome_seen': true,
  });
  final preferences = await SharedPreferences.getInstance();
  const installed = AppVersion(1, 0, 0, 1);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (handler != null) audioHandlerProvider.overrideWithValue(handler),
        deviceDecodesAtmosProvider.overrideWith((ref) => false),
        allTracksProvider.overrideWith((ref) => tracks),
        recentlyAddedProvider.overrideWith((ref) => tracks),
        recentlyPlayedProvider.overrideWith((ref) => const []),
        favoritesProvider.overrideWith((ref) => const []),
        libraryStatsProvider.overrideWith(
          (ref) => LibraryStats(
            trackCount: tracks.length,
            albumCount: 0,
            artistCount: 1,
            totalDuration: const Duration(minutes: 3) * tracks.length,
          ),
        ),
        playbackStateProvider.overrideWith(
          (ref) => Stream.value(PlaybackState()),
        ),
        currentMediaItemProvider.overrideWith(
          (ref) => Stream.value(nowPlaying),
        ),
        playbackPositionProvider.overrideWith(
          (ref) => Stream.value(Duration.zero),
        ),
        playbackErrorProvider.overrideWith((ref) => const Stream.empty()),
        scanControllerProvider.overrideWith(() => _IdleScanController(scan)),
        mostPlayedProvider.overrideWith((ref) => const []),
        installedVersionProvider.overrideWith((ref) => installed),
        updateServiceProvider.overrideWith(
          (ref) => UpdateService(
            manifestUrl: updateManifest == null
                ? ''
                : 'https://example.com/update.json',
            installed: installed,
            preferences: preferences,
            isIos: false,
            fetch: (_) async => updateManifest!,
          ),
        ),
      ],
      child: const NocTuneApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const phone = Size(390, 844);
  const tabletLandscape = Size(1280, 800);

  testWidgets('phones get the floating bottom bar', (tester) async {
    await _pumpApp(tester, size: phone);

    expect(find.byType(NocBottomBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final label in ['Home', 'Library', 'Settings', 'Search']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('a tablet in portrait keeps the bottom bar', (tester) async {
    await _pumpApp(tester, size: const Size(800, 1200));

    expect(find.byType(NocBottomBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('wide windows get a navigation rail', (tester) async {
    await _pumpApp(tester, size: tabletLandscape);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NocBottomBar), findsNothing);
  });

  group('bottom bar', () {
    final many = [for (var i = 0; i < 40; i++) _track('Track $i')];

    testWidgets('folds its tabs away while a list is scrolled', (tester) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Search'), findsNothing);

      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Folded: the two round side buttons replace the tabs.
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Library'), findsOneWidget);

      await tester.tap(find.byTooltip('Library'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Search'), findsNothing);
    });

    testWidgets('unfolds when the list is back at its top', (tester) async {
      await _pumpApp(tester, size: phone, tracks: many);
      await tester.tap(find.text('Library').last);
      await tester.pumpAndSettle();

      await tester.drag(find.text('Track 3'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Search'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Search'), findsNothing);
    });

    testWidgets('back returns to Home, then asks before leaving', (
      tester,
    ) async {
      await _pumpApp(tester, size: phone);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('APPEARANCE'), findsOneWidget);

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
    await _pumpApp(tester, size: phone, tracks: [_track('Aashish')]);

    expect(find.text('NocTune'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Plays'), findsOneWidget);
    // Nothing has been played yet, so the default list says so.
    expect(find.text('Nothing played yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Choose what the list shows'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently added').last);
    await tester.pumpAndSettle();
    expect(find.text('Aashish'), findsOneWidget);

    await tester.tap(find.text('Library').last);
    await tester.pumpAndSettle();
    expect(find.text('3:00'), findsOneWidget);
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
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
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

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('APPEARANCE'), findsOneWidget);

    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    expect(find.text('Search your library'), findsOneWidget);
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
}
