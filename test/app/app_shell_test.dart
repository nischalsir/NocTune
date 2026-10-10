import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/app.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
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

  testWidgets('phones get bottom navigation', (tester) async {
    await _pumpApp(tester, size: phone);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('tablets get a navigation rail', (tester) async {
    await _pumpApp(tester, size: tabletLandscape);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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

  testWidgets('home features a track and lists the library', (tester) async {
    await _pumpApp(tester, size: phone, tracks: [_track('Aashish')]);

    expect(find.text('RECENTLY ADDED'), findsOneWidget);
    expect(find.text('Aashish'), findsWidgets);

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
