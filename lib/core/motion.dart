import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// The path of a spring that is let go: from 0 it heads for 1 and settles
/// there, as a curve for an animation lasting [seconds].
///
/// [frequency] is how stiff the spring is, in radians a second: higher gets
/// there sooner. With [damping] at 1 it never passes its target; below 1 it
/// overshoots a little and comes back. [velocity] is the speed it already
/// has when it is let go, in distances a second, so a motion that replaces
/// one under way can carry on from it instead of starting from rest.
class SpringCurve extends Curve {
  const SpringCurve({
    required this.frequency,
    required this.seconds,
    this.damping = 1,
    this.velocity = 0,
  });

  final double frequency;
  final double seconds;
  final double damping;
  final double velocity;

  @override
  double transformInternal(double t) {
    final s = t * seconds;
    if (damping >= 1) {
      return 1 - (1 + (frequency - velocity) * s) * math.exp(-frequency * s);
    }
    final ringing = frequency * math.sqrt(1 - damping * damping);
    final swing = (damping * frequency - velocity) / ringing;
    return 1 -
        math.exp(-damping * frequency * s) *
            (math.cos(ringing * s) + swing * math.sin(ringing * s));
  }

  /// How fast the spring is moving at [t], in distances a second.
  double speedAt(double t) {
    final s = t * seconds;
    if (damping >= 1) {
      return math.exp(-frequency * s) *
          (velocity + frequency * (frequency - velocity) * s);
    }
    final ringing = frequency * math.sqrt(1 - damping * damping);
    final swing = (damping * frequency - velocity) / ringing;
    final decay = math.exp(-damping * frequency * s);
    return decay *
        (damping *
                frequency *
                (math.cos(ringing * s) + swing * math.sin(ringing * s)) +
            ringing * (math.sin(ringing * s) - swing * math.cos(ringing * s)));
  }
}

/// How far a spring that never overshoots has got [seconds] after it was let
/// go from rest: 0 at the start, 1 once it has settled.
double springSettle(double frequency, double seconds) => seconds <= 0
    ? 0
    : 1 - (1 + frequency * seconds) * math.exp(-frequency * seconds);
