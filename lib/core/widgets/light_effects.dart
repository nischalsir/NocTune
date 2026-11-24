import 'package:flutter/widgets.dart';

/// Whether the app draws with lighter effects: no live backdrop blur and no
/// decoration that moves all the time, for phones that can't keep up with
/// them. Navigation, the player and lyrics still move as usual.
///
/// Put once above the app; without it, effects are full.
class LightEffects extends InheritedWidget {
  const LightEffects({super.key, required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LightEffects>()?.on ?? false;

  @override
  bool updateShouldNotify(LightEffects oldWidget) => on != oldWidget.on;
}
