import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/equalizer/equalizer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fiveBands = (
  minDb: -15.0,
  maxDb: 15.0,
  centers: [60.0, 230.0, 910.0, 3600.0, 14000.0],
);

void main() {
  group('a curve', () {
    const curve = EqualizerCurve([
      (hz: 100, db: 6),
      (hz: 1000, db: 0),
      (hz: 10000, db: -4),
    ]);

    test('gives its own level at each of its points', () {
      expect(curve.levelAt(100), 6);
      expect(curve.levelAt(1000), 0);
      expect(curve.levelAt(10000), -4);
    });

    test('is level beyond its first and last point', () {
      expect(curve.levelAt(20), 6);
      expect(curve.levelAt(20000), -4);
    });

    test('moves evenly between points by pitch, not by hertz', () {
      // 316 Hz is halfway from 100 Hz to 1 kHz to the ear.
      expect(curve.levelAt(316.2278), closeTo(3, 0.001));
    });

    test('is laid over whatever bands the phone has, within its limits', () {
      const loud = EqualizerCurve([(hz: 60, db: 24), (hz: 14000, db: -24)]);
      const twoBands = (minDb: -10.0, maxDb: 10.0, centers: [60.0, 14000.0]);
      expect(loud.levelsFor(twoBands), [10, -10]);
      expect(curve.levelsFor(_fiveBands), hasLength(5));
    });
  });

  test('the ready-made shapes start with Flat and have names of their own', () {
    expect(builtInCurves.first.name, 'Flat');
    expect(builtInCurves.first.levelsFor(_fiveBands), everyElement(0));
    final names = [for (final curve in builtInCurves) curve.name];
    expect(names.toSet(), hasLength(names.length));
    expect(names, contains('Small speaker'));
  });

  test('Small speaker takes the deepest band down and adds nothing', () {
    final levels = builtInCurves
        .firstWhere((curve) => curve.name == 'Small speaker')
        .levelsFor(_fiveBands);
    expect(levels.first, lessThan(-6));
    expect(levels, everyElement(lessThanOrEqualTo(0)));
  });

  group('settings', () {
    test('start switched off, flat, with nothing saved', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = EqualizerSettings.load(
        await SharedPreferences.getInstance(),
      );
      expect(settings.enabled, isFalse);
      expect(settings.curve.name, 'Flat');
      expect(settings.preampDb, 0);
      expect(settings.saved, isEmpty);
    });

    test('come back as they were stored', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const mine = EqualizerCurve([
        (hz: 60, db: 4.5),
        (hz: 14000, db: -2),
      ], name: 'Car');
      const EqualizerSettings(
        enabled: true,
        curve: EqualizerCurve([(hz: 60, db: -3), (hz: 910, db: 2)]),
        preampDb: -4,
        saved: [mine],
      ).store(preferences);

      final settings = EqualizerSettings.load(preferences);
      expect(settings.enabled, isTrue);
      expect(settings.curve.name, isNull);
      expect(settings.curve.points, [
        (hz: 60.0, db: -3.0),
        (hz: 910.0, db: 2.0),
      ]);
      expect(settings.preampDb, -4);
      expect(settings.saved.single.name, 'Car');
      expect(settings.saved.single.points.first, (hz: 60.0, db: 4.5));
    });

    test('fall back to flat when what was stored cannot be read', () async {
      SharedPreferences.setMockInitialValues({
        'equalizer_curve': 'not a curve',
        'equalizer_saved': ['{', '{"name":"Ok","points":[[60,1]]}'],
        'equalizer_preamp': 40.0,
      });
      final settings = EqualizerSettings.load(
        await SharedPreferences.getInstance(),
      );
      expect(settings.curve.name, 'Flat');
      expect(settings.saved.single.name, 'Ok');
      expect(settings.preampDb, EqualizerSettings.maxPreampDb);
    });

    test('describe themselves for the Settings page', () {
      expect(const EqualizerSettings().summary, startsWith('Off.'));
      expect(
        const EqualizerSettings(
          enabled: true,
          curve: EqualizerCurve([(hz: 60, db: 5)], name: 'Rock'),
        ).summary,
        'On: Rock',
      );
      expect(
        const EqualizerSettings(
          enabled: true,
          curve: EqualizerCurve([(hz: 60, db: 5)]),
          preampDb: -3,
        ).summary,
        'On: your own setting, preamp -3 dB',
      );
    });
  });
}
