import 'package:flutter/widgets.dart';

/// Holds its child's animations still while the app is not the one in front:
/// under the notification shade or the control centre, behind a system
/// dialog, or unfocused in a split screen. They carry on when it is back.
///
/// The app is still on screen then, and every frame it draws has to be
/// drawn again by the system behind its own blur. Decoration that moves all
/// the time, such as sound bars while music plays, turned that into a new
/// frame on every tick of a 120 Hz screen and made the system's own
/// animations stutter over the app.
///
/// Put it around decoration. Leave out motion that is the content, such as
/// lyrics following a song.
class StillWhenCovered extends StatefulWidget {
  const StillWhenCovered({super.key, required this.child});

  final Widget child;

  @override
  State<StillWhenCovered> createState() => _StillWhenCoveredState();
}

class _StillWhenCoveredState extends State<StillWhenCovered> {
  late final AppLifecycleListener _lifecycle;

  // Unknown until the platform first reports it, which counts as in front.
  AppLifecycleState? _state = WidgetsBinding.instance.lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => setState(() => _state = state),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inFront = _state == null || _state == AppLifecycleState.resumed;
    return TickerMode(enabled: inFront, child: widget.child);
  }
}
