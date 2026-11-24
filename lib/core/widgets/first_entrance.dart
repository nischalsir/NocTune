import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lets the [EntranceItem]s under it come in one after the other, rising a
/// little as they fade in, the first time the page known as [id] shows its
/// rows while the app runs. Later visits, and rows that are scrolled to
/// afterwards, are simply there. With reduced motion on, nothing moves.
///
/// The rows' clock starts when the first of them is built, so a page that
/// is still loading its rows plays when they arrive.
class EntranceScope extends StatefulWidget {
  const EntranceScope({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope>
    with SingleTickerProviderStateMixin {
  // The pages that have played already in this run of the app.
  static final _played = <String>{};

  AnimationController? _clock;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_clock != null || _played.contains(widget.id)) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  void _start() {
    if (_started) return;
    _started = true;
    _played.add(widget.id);
    // After the frame that first builds the rows: they start from hidden.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _clock?.forward();
    });
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Entrance(clock: _clock, start: _start, child: widget.child);
}

class _Entrance extends InheritedWidget {
  const _Entrance({
    required this.clock,
    required this.start,
    required super.child,
  });

  final AnimationController? clock;
  final VoidCallback start;

  @override
  bool updateShouldNotify(_Entrance oldWidget) => clock != oldWidget.clock;
}

/// One row of an [EntranceScope]: the row at [index] comes in a moment after
/// the one before it.
class EntranceItem extends StatelessWidget {
  const EntranceItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  // How far apart the rows start, as shares of the scope's clock, and how
  // many rows apart at most: rows lower down come in with the last of these.
  static const _step = 0.05;
  static const _staggered = 10;
  static const _rise = 14.0;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Entrance>();
    final clock = scope?.clock;
    if (scope == null || clock == null || clock.isCompleted) return child;
    scope.start();
    final begin = math.min(index, _staggered) * _step;
    final curve = Interval(begin, begin + 0.5, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: clock,
      builder: (context, child) {
        final shown = curve.transform(clock.value);
        return Opacity(
          opacity: shown,
          child: Transform.translate(
            offset: Offset(0, _rise * (1 - shown)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
