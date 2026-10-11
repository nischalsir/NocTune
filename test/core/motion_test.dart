import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/core/motion.dart';

void main() {
  /// The curve's slope at [t], measured, in distances a second.
  double slope(SpringCurve curve, double t) {
    const step = 1e-5;
    return (curve.transform(t + step) - curve.transform(t - step)) /
        (2 * step * curve.seconds);
  }

  group('a spring that never overshoots', () {
    const curve = SpringCurve(frequency: 11.4, seconds: 1);

    test('starts at rest, and ends on its target', () {
      expect(curve.transform(0), 0);
      expect(curve.transform(1), 1);
      expect(curve.speedAt(0), 0);
      // All but there well before the end, so the end is no visible step.
      expect(curve.transform(0.999), closeTo(1, 0.001));
    });

    test('only ever moves towards its target', () {
      var before = 0.0;
      for (var i = 1; i <= 200; i++) {
        final now = curve.transform(i / 200);
        expect(now, greaterThanOrEqualTo(before));
        expect(now, lessThanOrEqualTo(1));
        before = now;
      }
    });

    test('is quick away: half way in about 150 ms, there in 600', () {
      expect(curve.transform(0.15), closeTo(0.5, 0.08));
      expect(curve.transform(0.6), greaterThan(0.99));
    });
  });

  test('a springy one passes its target a little and comes back', () {
    const curve = SpringCurve(frequency: 16.1, damping: 0.62, seconds: 0.7);

    final values = [for (var i = 0; i <= 200; i++) curve.transform(i / 200)];
    final highest = values.reduce((a, b) => a > b ? a : b);

    expect(highest, greaterThan(1.03));
    expect(highest, lessThan(1.15));
    expect(curve.transform(0.99), closeTo(1, 0.005));
  });

  group('let go already moving', () {
    test('sets off at that speed', () {
      for (final damping in [1.0, 0.7]) {
        final curve = SpringCurve(
          frequency: 11.4,
          damping: damping,
          seconds: 1,
          velocity: 3.5,
        );

        expect(curve.speedAt(0), closeTo(3.5, 1e-9));
        expect(slope(curve, 0.001), closeTo(3.5, 0.1));
      }
    });

    test('says how fast it is going at any moment', () {
      for (final curve in const [
        SpringCurve(frequency: 11.4, seconds: 1),
        SpringCurve(frequency: 11.4, seconds: 1, velocity: 6),
        SpringCurve(frequency: 18, damping: 0.78, seconds: 0.42),
        SpringCurve(frequency: 16.1, damping: 0.62, seconds: 0.7, velocity: -2),
      ]) {
        for (final t in [0.05, 0.2, 0.5, 0.8]) {
          expect(curve.speedAt(t), closeTo(slope(curve, t), 1e-3));
        }
      }
    });

    test('a move replaced mid-way carries on without a change of speed', () {
      // The list is half way through a move of 80 when it is sent 100
      // further.
      const first = SpringCurve(frequency: 11.4, seconds: 1);
      const at = 0.12;
      final gone = 80 * first.transform(at);
      final speed = 80 * first.speedAt(at);
      final left = 180 - gone;
      final second = SpringCurve(
        frequency: 11.4,
        seconds: 1,
        velocity: speed / left,
      );

      expect(left * second.speedAt(0), closeTo(speed, 1e-6));
      // And together they end where one move of 180 would.
      expect(gone + left * second.transform(1), closeTo(180, 1e-9));
    });
  });

  test('settling is the same path, by the clock', () {
    const curve = SpringCurve(frequency: 9, seconds: 2);

    expect(springSettle(9, 0), 0);
    expect(springSettle(9, -1), 0);
    for (final seconds in [0.05, 0.3, 1.0]) {
      expect(
        springSettle(9, seconds),
        closeTo(curve.transform(seconds / 2), 1e-12),
      );
    }
  });
}
