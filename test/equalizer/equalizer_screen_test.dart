import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/features/equalizer/equalizer_controller.dart';
import 'package:noctune/features/equalizer/equalizer_screen.dart';
import 'package:noctune/features/equalizer/equalizer_settings.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bands = (
  minDb: -15.0,
  maxDb: 15.0,
  centers: [60.0, 230.0, 910.0, 3600.0, 14000.0],
);

class _FakeHandler extends Fake implements NocAudioHandler {
  _FakeHandler({required bool bandsKnown}) {
    if (bandsKnown) _known.complete(_bands);
  }

  final _known = Completer<EqualizerBands>();
  final applied = <EqualizerSettings>[];

  @override
  Future<EqualizerBands> get equalizerBands => _known.future;

  @override
  Future<void> applyEqualizer(EqualizerSettings settings) async =>
      applied.add(settings);
}

Future<(_FakeHandler, ProviderContainer, SharedPreferences)> _pump(
  WidgetTester tester, {
  Map<String, Object> stored = const {},
  bool bandsKnown = true,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(stored);
  final preferences = await SharedPreferences.getInstance();
  final handler = _FakeHandler(bandsKnown: bandsKnown);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        audioHandlerProvider.overrideWithValue(handler),
      ],
      child: MaterialApp(
        theme: buildNocTheme(Brightness.dark, NocAccent.red),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const EqualizerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EqualizerScreen)),
  );
  return (handler, container, preferences);
}

Slider _band(WidgetTester tester, int index) =>
    tester.widget<Slider>(find.byKey(ValueKey('equalizer-band-$index')));

Slider _preamp(WidgetTester tester) =>
    tester.widget<Slider>(find.byKey(const ValueKey('equalizer-preamp')));

const _on = <String, Object>{'equalizer_enabled': true};

void main() {
  testWidgets('starts switched off, with its controls at rest', (tester) async {
    final (handler, container, _) = await _pump(tester);

    expect(
      tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
      isFalse,
    );
    for (var index = 0; index < 5; index++) {
      expect(_band(tester, index).value, 0);
      expect(_band(tester, index).onChanged, isNull);
    }
    expect(_preamp(tester).onChanged, isNull);
    expect(container.read(equalizerProvider).enabled, isFalse);
    expect(handler.applied, isEmpty);
  });

  testWidgets('the switch turns it on, remembers it and tells the player', (
    tester,
  ) async {
    final (handler, _, preferences) = await _pump(tester);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(handler.applied.single.enabled, isTrue);
    expect(preferences.getBool('equalizer_enabled'), isTrue);
    expect(_band(tester, 0).onChanged, isNotNull);
    expect(_preamp(tester).onChanged, isNotNull);
  });

  testWidgets('shows one slider for each band the phone has', (tester) async {
    await _pump(tester, stored: _on);

    expect(find.text('60 Hz'), findsOneWidget);
    expect(find.text('230 Hz'), findsOneWidget);
    expect(find.text('910 Hz'), findsOneWidget);
    expect(find.text('3.6 kHz'), findsOneWidget);
    expect(find.text('14 kHz'), findsOneWidget);
    expect(_band(tester, 0).min, -15);
    expect(_band(tester, 0).max, 15);
  });

  testWidgets('a ready-made shape moves the sliders and reaches the player', (
    tester,
  ) async {
    final (handler, container, _) = await _pump(tester, stored: _on);

    await tester.tap(find.text('Bass boost'));
    await tester.pumpAndSettle();

    final curve = container.read(equalizerProvider).curve;
    expect(curve.name, 'Bass boost');
    expect(_band(tester, 0).value, greaterThan(0));
    expect(_band(tester, 0).value, curve.levelsFor(_bands).first);
    expect(handler.applied.last.curve.name, 'Bass boost');
  });

  testWidgets('moving a band makes the setting your own', (tester) async {
    final (handler, container, preferences) = await _pump(tester, stored: _on);
    await tester.ensureVisible(find.text('Rock'));
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    final before = container.read(equalizerProvider).curve.levelsFor(_bands);

    _band(tester, 2).onChanged!(7);
    await tester.pumpAndSettle();

    final curve = container.read(equalizerProvider).curve;
    expect(curve.name, isNull);
    expect(curve.levelsFor(_bands), [
      before[0],
      before[1],
      7,
      before[3],
      before[4],
    ]);
    expect(handler.applied.last.curve.levelsFor(_bands)[2], 7);
    expect(_band(tester, 2).value, 7);
    expect(EqualizerSettings.load(preferences).curve.levelsFor(_bands)[2], 7);
  });

  testWidgets('the preamp is kept and sent to the player', (tester) async {
    final (handler, _, preferences) = await _pump(tester, stored: _on);

    _preamp(tester).onChanged!(-5);
    await tester.pumpAndSettle();

    expect(handler.applied.last.preampDb, -5);
    expect(preferences.getDouble('equalizer_preamp'), -5);
    expect(find.text('-5 dB'), findsOneWidget);
    expect(_preamp(tester).min, EqualizerSettings.minPreampDb);
    expect(_preamp(tester).max, EqualizerSettings.maxPreampDb);
  });

  testWidgets('saves the setting under a name, then deletes it', (
    tester,
  ) async {
    final (_, container, preferences) = await _pump(tester, stored: _on);
    _band(tester, 0).onChanged!(-6);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save as preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Car');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(container.read(equalizerProvider).curve.name, 'Car');
    expect(container.read(equalizerProvider).saved.single.name, 'Car');
    expect(EqualizerSettings.load(preferences).saved.single.name, 'Car');
    expect(find.text('Car'), findsOneWidget);

    // Another shape, then back to the saved one.
    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle();
    expect(_band(tester, 0).value, 0);
    await tester.ensureVisible(find.text('Car'));
    await tester.tap(find.text('Car'));
    await tester.pumpAndSettle();
    expect(_band(tester, 0).value, -6);

    await tester.tap(find.text('Delete "Car"'));
    await tester.pumpAndSettle();
    expect(container.read(equalizerProvider).saved, isEmpty);
    expect(EqualizerSettings.load(preferences).saved, isEmpty);
    // The sound stays as it was; only the name goes.
    expect(_band(tester, 0).value, -6);
    expect(container.read(equalizerProvider).curve.name, isNull);
  });

  testWidgets('a ready-made name cannot be taken by a saved setting', (
    tester,
  ) async {
    final (_, container, _) = await _pump(tester, stored: _on);

    await tester.tap(find.text('Save as preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' rock ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(container.read(equalizerProvider).saved, isEmpty);
  });

  testWidgets('Reset goes back to flat with no preamp', (tester) async {
    final (handler, container, _) = await _pump(
      tester,
      stored: {..._on, 'equalizer_preamp': -6.0},
    );
    await tester.ensureVisible(find.text('Rock'));
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    final settings = container.read(equalizerProvider);
    expect(settings.curve.name, 'Flat');
    expect(settings.preampDb, 0);
    expect(settings.enabled, isTrue);
    expect(handler.applied.last.preampDb, 0);
  });

  testWidgets('says what it is waiting for until the phone gives its bands', (
    tester,
  ) async {
    await _pump(tester, stored: _on, bandsKnown: false);

    expect(find.byKey(const ValueKey('equalizer-band-0')), findsNothing);
    expect(find.textContaining('Play a song'), findsOneWidget);
    // The rest still works.
    expect(_preamp(tester).onChanged, isNotNull);
  });

  testWidgets('fits a small phone with large text', (tester) async {
    await _pump(tester, stored: _on, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
