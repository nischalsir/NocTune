import 'package:flutter/material.dart';

/// Shared-element tag: the mini-player's cover grows into the player's cover.
const kNowPlayingArtworkHero = 'now-playing-artwork';

const _entranceCurve = Curves.easeOutCubic;

/// Slides the full player up over the app. Dragging down anywhere that isn't
/// a control moves the page with the finger; letting go either closes it or
/// settles it back, depending on how far and how fast it was moving.
///
/// The drag-following approach is modelled on the player route in
/// SpotiFLAC-Mobile (MIT licence, © zarzet).
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute({required this.child}) : super(fullscreenDialog: true);

  final Widget child;

  // True from the first drag until the page is fully open again. While set,
  // the page position maps straight onto the animation value, so it stays
  // under the finger and nothing jumps when the finger lifts.
  bool _followingFinger = false;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  void _startDrag() {
    final controller = this.controller;
    if (controller == null) return;
    controller.stop();
    if (!_followingFinger) {
      // Re-express the current on-screen position in linear terms, so
      // grabbing the page mid-animation doesn't move it.
      controller.value = _entranceCurve.transform(controller.value);
      _followingFinger = true;
      changedInternalState();
    }
  }

  void _updateDrag(DragUpdateDetails details, double pageHeight) {
    controller?.value -= (details.primaryDelta ?? 0) / pageHeight;
  }

  void _endDrag(DragEndDetails details, double pageHeight) {
    final controller = this.controller;
    if (controller == null) return;
    // Pages per second, positive when moving down.
    final velocity = (details.primaryVelocity ?? 0) / pageHeight;
    // A downward flick closes it; so does letting go below the fold while
    // not moving back up. The direction of travel decides, not just position.
    if (velocity > 1.0 || (velocity >= 0 && controller.value < 0.7)) {
      navigator?.pop();
    } else {
      _settleOpen();
    }
  }

  void _settleOpen() {
    controller
        ?.animateTo(
          1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (controller?.value == 1) {
            _followingFinger = false;
            changedInternalState();
          }
        });
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final pageHeight = MediaQuery.sizeOf(context).height;
    // Sliders, buttons and scrolling lists inside the page win their own
    // gestures; this only receives drags on the open areas and the cover.
    return GestureDetector(
      onVerticalDragStart: (_) => _startDrag(),
      onVerticalDragUpdate: (details) => _updateDrag(details, pageHeight),
      onVerticalDragEnd: (details) => _endDrag(details, pageHeight),
      onVerticalDragCancel: _settleOpen,
      child: child,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Reduced motion: a cross-fade in place of a moving page.
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final progress = _followingFinger
        ? animation
        : CurvedAnimation(
            parent: animation,
            curve: _entranceCurve,
            reverseCurve: Curves.easeInCubic,
          );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(progress),
      child: child,
    );
  }
}
