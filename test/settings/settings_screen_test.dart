import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/playlist.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/playback/audio_capabilities.dart';
import 'package:noctune/features/settings/settings_controller.dart';
import 'package:noctune/features/settings/settings_screen.dart';
import 'package:noctune/features/startup/startup_prompts.dart';
import 'package:noctune/features/startup/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepository extends Fake implements LibraryRepository {
  int historyCleared = 0;

  @override
  Future<void> clearListeningHistory() async => historyCleared++;
}

class _IdleScanController extends ScanController {
  @override
  ScanState build() => const ScanIdle();
}

const _installed = AppVersion(1, 2, 0, 3);

Future<(_FakeRepository, ProviderContainer)> _pump(
  WidgetTester tester, {
  Future<String> Function(Uri url)? fetch,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = _FakeRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        libraryRepositoryProvider.overrideWithValue(repository),
        libraryStatsProvider.overrideWith(
          (ref) => const LibraryStats(
            trackCount: 319,
            albumCount: 40,
            artistCount: 25,
            totalDuration: Duration(hours: 21, minutes: 4),
          ),
        ),
        deviceDecodesAtmosProvider.overrideWith((ref) => false),
        scanControllerProvider.overrideWith(_IdleScanController.new),
        installedVersionProvider.overrideWith((ref) => _installed),
        updateServiceProvider.overrideWith(
          (ref) => UpdateService(
            manifestUrl: fetch == null ? '' : 'https://example.com/update.json',
            installed: _installed,
            preferences: preferences,
            isIos: false,
            fetch: fetch ?? (_) async => '',
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildNocTheme(Brightness.dark, NocAccent.red),
        home: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(SettingsScreen)),
  );
  return (repository, container);
}

/// Scrolls the page until [finder] is on screen and can be tapped.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups its settings under clear headings', (tester) async {
    await _pump(tester);

    for (final heading in [
      'APPEARANCE',
      'PLAYBACK',
      'LYRICS',
      'AUDIO',
      'LIBRARY',
      'PRIVACY',
      'ABOUT',
    ]) {
      await _reveal(tester, find.text(heading));
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
  });

  testWidgets('shows the installed version and build number', (tester) async {
    await _pump(tester);

    await _reveal(tester, find.text('Version 1.2.0 (build 3)'));
    expect(find.text('Version 1.2.0 (build 3)'), findsOneWidget);
  });

  testWidgets('shows what the library holds', (tester) async {
    await _pump(tester);

    await _reveal(tester, find.textContaining('319 tracks'));
    expect(find.text('319 tracks · 40 albums · 25 artists'), findsOneWidget);
  });

  testWidgets('clearing the listening history asks first', (tester) async {
    final (repository, _) = await _pump(tester);
    await _reveal(tester, find.text('Clear listening history'));

    await tester.tap(find.text('Clear listening history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear listening history?'), findsOneWidget);
    expect(repository.historyCleared, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clear listening history?'), findsNothing);
    expect(repository.historyCleared, 0);

    await tester.tap(find.text('Clear listening history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(repository.historyCleared, 1);
    expect(find.text('Listening history cleared.'), findsOneWidget);
  });

  testWidgets('choices are saved as they are made', (tester) async {
    final (_, container) = await _pump(tester);
    final preferences = await SharedPreferences.getInstance();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(preferences.getString('theme_mode'), 'light');

    await _reveal(tester, find.text('Fold the navigation bar'));
    await tester.tap(find.text('Fold the navigation bar'));
    await tester.pumpAndSettle();
    expect(preferences.getBool('fold_navigation_on_scroll'), isFalse);
    expect(container.read(settingsProvider).foldNavigationOnScroll, isFalse);

    await _reveal(tester, find.text('Wave seek bar'));
    await tester.tap(find.text('Wave seek bar'));
    await tester.pumpAndSettle();
    expect(preferences.getBool('wave_seek_bar'), isFalse);
    expect(container.read(settingsProvider).waveSeekBar, isFalse);

    await _reveal(tester, find.byType(Slider));
    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    final scale = container.read(settingsProvider).lyricsScale;
    expect(scale, greaterThan(1));
    expect(preferences.getDouble('lyrics_scale'), scale);
  });

  testWidgets('the theme can be chosen by sliding across its selector', (
    tester,
  ) async {
    await _pump(tester);
    final preferences = await SharedPreferences.getInstance();

    // From System, across Light, let go on Dark.
    final finger = await tester.startGesture(
      tester.getCenter(find.text('System')),
    );
    for (var i = 0; i < 6; i++) {
      await finger.moveBy(
        Offset(
          (tester.getCenter(find.text('Dark')).dx -
                  tester.getCenter(find.text('System')).dx) /
              6,
          0,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await tester.pumpAndSettle();

    expect(preferences.getString('theme_mode'), 'dark');
  });

  testWidgets('a switch can be flipped by itself or by its row', (
    tester,
  ) async {
    final (_, container) = await _pump(tester);
    await _reveal(tester, find.text('Wave seek bar'));
    final toggle = find.descendant(
      of: find.ancestor(
        of: find.text('Wave seek bar'),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(CupertinoSwitch),
    );
    expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).waveSeekBar, isFalse);
    expect(tester.widget<CupertinoSwitch>(toggle).value, isFalse);

    await tester.tap(find.text('Wave seek bar'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).waveSeekBar, isTrue);

    // Read out as one switch with its title.
    final handle = tester.ensureSemantics();
    final row = tester.getSemantics(find.text('Wave seek bar'));
    expect(row.label, startsWith('Wave seek bar'));
    expect(row, isSemantics(hasToggledState: true, isToggled: true));
    handle.dispose();
  });

  testWidgets('no update row when update checks are not set up', (
    tester,
  ) async {
    await _pump(tester);

    await _reveal(tester, find.text('Open-source licences'));
    expect(find.text('Check for updates'), findsNothing);
    expect(find.textContaining('makes no network requests'), findsOneWidget);
  });

  group('checking for updates', () {
    testWidgets('says so when nothing newer exists', (tester) async {
      await _pump(
        tester,
        fetch: (_) async =>
            '{"version": "1.2.0", "url": "https://example.com/r"}',
      );
      await _reveal(tester, find.text('Check for updates'));

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('NocTune is up to date.'), findsOneWidget);
    });

    testWidgets('does not claim to be up to date when the check fails', (
      tester,
    ) async {
      await _pump(tester, fetch: (_) async => throw Exception('offline'));
      await _reveal(tester, find.text('Check for updates'));

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('NocTune is up to date.'), findsNothing);
      expect(find.textContaining("Couldn't check for updates"), findsOneWidget);
    });

    testWidgets('announces a newer release', (tester) async {
      await _pump(
        tester,
        fetch: (_) async =>
            '{"version": "1.3.0", "url": "https://example.com/r", '
            '"notes": ["Better lyrics"]}',
      );
      await _reveal(tester, find.text('Check for updates'));

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Better lyrics'), findsOneWidget);
    });
  });

  testWidgets('opens the open-source licences page', (tester) async {
    await _pump(tester);
    await _reveal(tester, find.text('Open-source licences'));

    await tester.tap(find.text('Open-source licences'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('survives large text on a small phone', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
