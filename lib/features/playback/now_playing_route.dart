import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Shared-element tag: the mini-player's cover grows into the player's cover.
const kNowPlayingArtworkHero = 'now-playing-artwork';

/// Marks the mini-player's surface, which the full player grows out of.
final miniPlayerSurfaceKey = GlobalKey();

/// How far the growing player has pushed the navigation bar down, in logical
/// pixels. The bar moves its tabs by this much, which keeps them just under
/// the player's lower edge until they are off the screen.
final playerBarPush = ValueNotifier<double>(0);

const _entranceCurve = Curves.easeOutCubic;

// Slow to start, so the mini-player has dissolved into the player before the
// surface has grown far.
const _growCurve = Curves.fastOutSlowIn;

/// The part of the transition over which the page fades in at the start,
/// and out at the end of closing.
const _dissolve = 0.2;

/// Opens the full player out of the mini-player: its surface grows upwards
/// and downwards from where the mini-player is until it fills the screen,
/// pushing the navigation bar down ahead of its lower edge, and shrinks back
/// into the mini-player on the way out. With no mini-player on screen the
/// page slides up over the app instead.
///
/// Dragging down anywhere that isn't a control moves the page with the
/// finger; letting go either closes it or settles it back, depending on how
/// far and how fast it was moving.
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute({required this.child}) : super(fullscreenDialog: true);

  final Widget child;

  // Where the mini-player was when the player was opened.
  Rect? _origin;

  /// Downward speed, in page-heights per second, that counts as a flick.
  static const _flingToClose = 0.9;

  /// Released at rest with less than this much of the page still showing,
  /// it closes.
  static const _closeBelow = 0.66;

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

  @override
  void install() {
    super.install();
    // With reduced motion the page cross-fades in place and nothing moves.
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      return;
    }
    final surface = miniPlayerSurfaceKey.currentContext?.findRenderObject();
    if (surface is RenderBox && surface.hasSize) {
      _origin = surface.localToGlobal(Offset.zero) & surface.size;
      // The controller, not [animation]: for the page's first frame, kept
      // offstage to measure it, [animation] reads as already complete.
      controller!.addListener(_pushBar);
    }
  }

  /// How far the surface has grown, from the mini-player (0) to the whole
  /// screen (1).
  double get _grown {
    final value = controller!.value;
    return _followingFinger ? value : _growCurve.transform(value);
  }

  void _pushBar() {
    final screen = navigator?.context.findRenderObject();
    if (screen is! RenderBox) return;
    playerBarPush.value = (screen.size.height - _origin!.bottom) * _grown;
  }

  void _startDrag() {
    final controller = this.controller;
    if (controller == null) return;
    controller.stop();
    if (!_followingFinger) {
      // Re-express the current on-screen position in linear terms, so
      // grabbing the page mid-animation doesn't move it.
      final position = (_origin == null ? _entranceCurve : _growCurve)
          .transform(controller.value);
      _followingFinger = true;
      controller.value = position;
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
    if (velocity > _flingToClose ||
        (velocity >= 0 && controller.value < _closeBelow)) {
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
    final origin = _origin;
    if (origin != null) {
      final screen = Offset.zero & MediaQuery.sizeOf(context);
      final corner = math.min(32.0, origin.height / 2);
      return AnimatedBuilder(
        animation: animation,
        builder: (context, page) {
          final grown = _grown;
          // The page keeps its size and place; the surface it shows through
          // is what grows.
          return ClipRRect(
            clipper: _SurfaceClipper(
              RRect.fromRectAndRadius(
                Rect.lerp(origin, screen, grown)!,
                Radius.circular(lerpDouble(corner, 0, grown)!),
              ),
            ),
            child: Opacity(
              opacity: (controller!.value / _dissolve).clamp(0.0, 1.0),
              child: page,
            ),
          );
        },
        child: child,
      );
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

class _SurfaceClipper extends CustomClipper<RRect> {
  const _SurfaceClipper(this.surface);

  final RRect surface;

  @override
  RRect getClip(Size size) => surface;

  @override
  bool shouldReclip(_SurfaceClipper old) => old.surface != surface;
}
