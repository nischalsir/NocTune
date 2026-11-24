import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lets the [EntranceItem]s under it come in one after the other, rising a
/// little as they fade in, the first time the page known as [id] shows its
/// rows while the app runs. Rows further down rise in the same way as they
/// are scrolled into view, once each while the page is open; later visits
/// show the rows already on screen as they are. With reduced motion on,
/// nothing moves.
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

  // The rows that have come in, or were on screen already, on this visit.
  final _seen = <int>{};

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
  Widget build(BuildContext context) => _Entrance(
    clock: _clock,
    start: _start,
    seen: _seen,
    moves: !MediaQuery.disableAnimationsOf(context),
    child: widget.child,
  );
}

class _Entrance extends InheritedWidget {
  const _Entrance({
    required this.clock,
    required this.start,
    required this.seen,
    required this.moves,
    required super.child,
  });

  final AnimationController? clock;
  final VoidCallback start;
  final Set<int> seen;
  final bool moves;

  @override
  bool updateShouldNotify(_Entrance oldWidget) =>
      clock != oldWidget.clock || moves != oldWidget.moves;
}

/// One row of an [EntranceScope]: the row at [index] comes in a moment after
/// the one before it, or, if it is built out of sight, as it is scrolled
/// into view.
class EntranceItem extends StatefulWidget {
  const EntranceItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<EntranceItem>
    with SingleTickerProviderStateMixin {
  // How far apart the rows start, as shares of the scope's clock, and how
  // many rows apart at most: rows lower down come in with the last of these.
  static const _step = 0.05;
  static const _staggered = 10;
  static const _rise = 14.0;

  /// Whether this row has been placed yet: on screen, or waiting below.
  bool _placed = false;

  /// The row's own entrance, once it waits out of sight to be scrolled to.
  AnimationController? _own;
  ScrollPosition? _position;

  /// Whether the row has been drawn through [_rising] already.
  bool _wrapped = false;

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _own?.dispose();
    super.dispose();
  }

  /// After the row's first layout: a row on screen stays as it is, one out
  /// of sight hides until it is scrolled into view.
  void _place(_Entrance scope) {
    if (_placed) return;
    _placed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final position = Scrollable.maybeOf(context)?.position;
      if (position == null || _inView()) {
        scope.seen.add(widget.index);
        return;
      }
      setState(() {
        _own = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 380),
        );
      });
      _position = position..addListener(_onScroll);
    });
  }

  // The list moves before it is laid out again, so where the row is shows
  // only after the frame.
  bool _checking = false;

  void _onScroll() {
    if (_checking) return;
    _checking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checking = false;
      _check();
    });
  }

  void _check() {
    if (!mounted || !_inView()) return;
    _position?.removeListener(_onScroll);
    _position = null;
    context
        .getInheritedWidgetOfExactType<_Entrance>()
        ?.seen
        .add(widget.index);
    _own?.forward();
  }

  /// Whether any of the row is inside its scrolling list's window.
  bool _inView() {
    final row = context.findRenderObject();
    final view = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (row is! RenderBox || view is! RenderBox) return true;
    if (!row.attached || !row.hasSize || !view.hasSize) return true;
    final rect = MatrixUtils.transformRect(
      row.getTransformTo(view),
      Offset.zero & row.size,
    );
    return rect.bottom > 0 &&
        rect.top < view.size.height &&
        rect.right > 0 &&
        rect.left < view.size.width;
  }

  /// The row, rising as [shown] goes from 0 to 1 while [clock] runs.
  Widget _rising(Listenable clock, double Function() shown) => AnimatedBuilder(
    animation: clock,
    builder: (context, child) {
      final at = shown();
      return Opacity(
        opacity: at,
        child: Transform.translate(
          offset: Offset(0, _rise * (1 - at)),
          child: child,
        ),
      );
    },
    child: widget.child,
  );

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Entrance>();
    if (scope == null || !scope.moves) return widget.child;

    final own = _own;
    if (own != null) {
      // A row still waiting may have been brought into view without a
      // scroll, by the list growing or the window turning.
      if (own.isDismissed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      }
      return _rising(own, () => Curves.easeOutCubic.transform(own.value));
    }

    if (!scope.seen.contains(widget.index)) _place(scope);

    final clock = scope.clock;
    if (clock != null && !clock.isCompleted) {
      scope.start();
      _wrapped = true;
      final begin = math.min(widget.index, _staggered) * _step;
      final curve = Interval(begin, begin + 0.5, curve: Curves.easeOutCubic);
      return _rising(clock, () => curve.transform(clock.value));
    }
    // Once wrapped, the row keeps its place in the tree, so the tile
    // inside is never rebuilt from scratch.
    return _wrapped ? _rising(clock!, () => 1) : widget.child;
  }
}
