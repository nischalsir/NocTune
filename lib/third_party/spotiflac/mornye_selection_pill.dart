// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// Copyright (c) 2026 zarzet, MIT licence. See LICENSE in this folder.
// Changes for NocTune: imports, app-specific hooks, and the hand-over between
// the flat pill and the glass lens: the pill marks the selection at rest, the
// lens carries it while it moves, and the two are never shown together. The
// selection travels and the lens lifts on springs rather than plain eases.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../core/motion.dart';
import 'mornye_liquid_backdrop.dart';

Future<ui.FragmentProgram>? _selectionMaskProgram;
const _heldWidthGrowth = 0.28;
const _heldHeightGrowth = 0.24;
const _pillRadius = 32.0;
// NocTune: the selection moves to a tab on a spring that passes it by a
// touch and settles. After a slide, the glass that carries it stays for
// [_settleTime] while it arrives.
const _travelTime = Duration(milliseconds: 420);
const _travelCurve = SpringCurve(frequency: 18, damping: 0.78, seconds: 0.42);
const _settleTime = Duration(milliseconds: 260);

/// Selection with a transient lens over the fixed-size foreground while held.
/// It refracts both the bar's backdrop and its icons, rendered only once.
class MornyeSelectionPill extends StatefulWidget {
  const MornyeSelectionPill({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(4),
    this.liquidInteraction = false,
    this.selectionColor,
    this.maskItemForeground = true,
    this.interactionBuilder,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Widget Function(BuildContext context, int index, bool selected)
  itemBuilder;
  final EdgeInsets padding;
  final bool liquidInteraction;

  /// Recolors the foreground under the moving pill instead of switching an
  /// entire item at a tab boundary. Builders receive `selected: false` in this
  /// mode so the unmasked foreground retains its normal color.
  final Color? selectionColor;
  final bool maskItemForeground;

  /// Lets the bar animate its glass behind the fixed-size foreground using the
  /// same press/release animation as the selection lens.
  final Widget Function(BuildContext context, double progress, Widget child)?
  interactionBuilder;

  @override
  State<MornyeSelectionPill> createState() => _MornyeSelectionPillState();
}

class _MornyeSelectionPillState extends State<MornyeSelectionPill>
    with SingleTickerProviderStateMixin {
  int? _dragIndex;
  bool _dragCancelled = false;
  bool _pressed = false;
  int? _pressedIndex;
  double? _dragAlignment;
  int? _activePointer;
  final _foregroundKey = GlobalKey();
  Timer? _settleTimer;
  late final AnimationController _pressController;
  late final CurvedAnimation _pressAnimation;
  late final CurvedAnimation _liftAnimation;
  ui.FragmentProgram? _maskProgram;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    // NocTune: the glass stays up until it has arrived, even after a quick
    // tap, and only then gives way to the flat pill.
    _pressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_pressed) {
        _pressController.reverse();
      }
    });
    _pressAnimation = CurvedAnimation(
      parent: _pressController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    )..addListener(() => setState(() {}));
    // NocTune: the lens's size follows the same press on curves that pass
    // their end a little, so it springs up under the finger and settles
    // back when it is let go.
    _liftAnimation = CurvedAnimation(
      parent: _pressController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );
    if (widget.selectionColor != null) unawaited(_loadMaskProgram());
  }

  Future<void> _loadMaskProgram() async {
    try {
      final program = await (_selectionMaskProgram ??=
          ui.FragmentProgram.fromAsset(
            'assets/shaders/mornye_selection_mask.frag',
          ));
      if (mounted) setState(() => _maskProgram = program);
    } catch (error) {
      debugPrint('Mornye selection mask unavailable: $error');
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _pressAnimation.dispose();
    _liftAnimation.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MornyeSelectionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionColor == null && widget.selectionColor != null) {
      unawaited(_loadMaskProgram());
    }
    if (oldWidget.labels.length != widget.labels.length ||
        oldWidget.selectedIndex != widget.selectedIndex) {
      _dragIndex = null;
      _dragAlignment = null;
      _pressedIndex = null;
    }
    // NocTune: a page changed from elsewhere (the back button, a shortcut)
    // moves the selection in glass too. Not while the bar is folded away.
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        !_pressed &&
        _lensEnabled &&
        TickerMode.valuesOf(context).enabled) {
      _pressController.forward();
    }
  }

  bool get _lensEnabled =>
      widget.liquidInteraction &&
      ui.ImageFilter.isShaderFilterSupported &&
      !MediaQuery.disableAnimationsOf(context) &&
      !MediaQuery.highContrastOf(context);

  // NocTune: the finger has left. Glass that is still coming up finishes
  // first (see the status listener). Glass that is fully up goes once the
  // selection has stopped: at once after a press, and after a slide when the
  // selection has settled onto its tab.
  void _releaseGlass() {
    if (!_pressController.isCompleted) return;
    _settleTimer?.cancel();
    if (_dragAlignment == null) {
      _pressController.reverse();
      return;
    }
    _settleTimer = Timer(_settleTime, () {
      if (mounted && !_pressed) _pressController.reverse();
    });
  }

  void _preview(double x, double width) {
    if (width <= 0 || widget.labels.isEmpty) return;
    final visual = (x / width * widget.labels.length).floor().clamp(
      0,
      widget.labels.length - 1,
    );
    final logical = Directionality.of(context) == TextDirection.rtl
        ? widget.labels.length - 1 - visual
        : visual;
    final halfItem = width / widget.labels.length / 2;
    final position = width <= halfItem * 2
        ? 0.0
        : ((x.clamp(halfItem, width - halfItem) - halfItem) /
                      (width - 2 * halfItem)) *
                  2 -
              1;
    setState(() {
      _dragIndex = logical;
      _dragAlignment = Directionality.of(context) == TextDirection.rtl
          ? -position
          : position;
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.labels.length;
    if (count == 0) return const SizedBox.shrink();
    final selected = _dragIndex ?? _pressedIndex ?? widget.selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    final lensEnabled = _lensEnabled;
    final pressProgress = lensEnabled ? _pressAnimation.value : 0.0;
    // NocTune: how far the lens has grown, which may pass 1 or dip under 0.
    final lift = lensEnabled ? _liftAnimation.value : 0.0;
    // NocTune: how much of the flat pill shows. None while the glass is up.
    final rest = 1 - pressProgress;
    final content = Listener(
      // An accepted drag can end with a PointerCancelEvent. Do not navigate
      // when the OS interrupts the gesture (e.g. opening system controls).
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _dragCancelled = false;
        if (!lensEnabled || _pressed) return;
        final box = context.findRenderObject()! as RenderBox;
        final width = box.size.width - widget.padding.horizontal;
        if (width <= 0) return;
        final visual =
            ((event.localPosition.dx - widget.padding.left) / width * count)
                .floor()
                .clamp(0, count - 1);
        setState(() {
          _pressed = true;
          _pressedIndex = Directionality.of(context) == TextDirection.rtl
              ? count - visual - 1
              : visual;
        });
        _pressController.forward();
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _releaseGlass();
        setState(() {
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _releaseGlass();
        setState(() {
          _dragCancelled = true;
          _pressed = false;
          _pressedIndex = null;
          _dragAlignment = null;
        });
      },
      child: Padding(
        padding: widget.padding,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (event) =>
                _preview(event.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (event) =>
                _preview(event.localPosition.dx, constraints.maxWidth),
            onHorizontalDragEnd: (_) {
              final index = _dragIndex;
              setState(() {
                _dragIndex = null;
                _dragAlignment = null;
              });
              if (index != null && !_dragCancelled) widget.onChanged(index);
            },
            onHorizontalDragCancel: () => setState(() {
              _dragIndex = null;
              _dragAlignment = null;
            }),
            child: Stack(
              fit: StackFit.passthrough,
              clipBehavior: Clip.none,
              children: [
                // NocTune: the flat pill marks the selection at rest. It
                // fades out as the glass lens comes up and returns once the
                // lens has gone, so the two are never seen together.
                if (selected >= 0 && selected < count)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedAlign(
                        duration:
                            _dragAlignment != null ||
                                MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : _travelTime,
                        curve: _travelCurve,
                        alignment: AlignmentDirectional(
                          _dragAlignment ??
                              (count == 1
                                  ? 0
                                  : -1 + 2 * selected / (count - 1)),
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1 / count,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(
                                alpha:
                                    rest *
                                    (scheme.brightness == Brightness.dark
                                        ? 0.12
                                        : 0.08),
                              ),
                              borderRadius: BorderRadius.circular(_pillRadius),
                              border: Border.all(
                                color: scheme.onSurface.withValues(
                                  alpha: 0.05 * rest,
                                ),
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.08 * rest,
                                  ),
                                  blurRadius: 1,
                                  offset: const Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                _foreground(
                  selected,
                  count,
                  lift,
                  Row(
                    key: _foregroundKey,
                    children: [
                      for (var index = 0; index < count; index++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: index == widget.selectedIndex,
                            label: widget.labels[index],
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  _pillRadius,
                                ),
                                // The moving pill supplies press feedback. An
                                // ink highlight would leave a colored patch on
                                // the tab where the drag started.
                                splashFactory: widget.selectionColor == null
                                    ? null
                                    : NoSplash.splashFactory,
                                highlightColor: widget.selectionColor == null
                                    ? null
                                    : Colors.transparent,
                                onTap: () => widget.onChanged(index),
                                child: ExcludeSemantics(
                                  child: _item(context, index, selected),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // The lens must sample the foreground as well as the page.
                // Below the icons it would look like a rim on a flat backdrop.
                if (lensEnabled && selected >= 0 && selected < count)
                  _interactionLens(selected, count, pressProgress, lift),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.interactionBuilder?.call(context, pressProgress, content) ??
        content;
  }

  Widget _item(BuildContext context, int index, int selected) {
    final child = widget.itemBuilder(
      context,
      index,
      widget.selectionColor == null && index == selected,
    );
    return widget.maskItemForeground
        ? MornyeSelectionForeground(child: child)
        : child;
  }

  Widget _foreground(int selected, int count, double lift, Widget child) {
    final color = widget.selectionColor;
    if (color == null) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(
        end:
            _dragAlignment ??
            (count == 1 ? 0 : -1 + 2 * selected / (count - 1)),
      ),
      duration:
          _dragAlignment != null || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : _travelTime,
      curve: _travelCurve,
      builder: (context, alignment, child) => _SelectionForegroundScope(
        rowKey: _foregroundKey,
        alignment: Directionality.of(context) == TextDirection.rtl
            ? -alignment
            : alignment,
        count: count,
        scaleX: 1 + _heldWidthGrowth * lift,
        scaleY: 1 + _heldHeightGrowth * lift,
        program: _maskProgram,
        color: selected >= 0 && selected < count
            ? color
            : color.withValues(alpha: 0),
        child: child!,
      ),
      child: child,
    );
  }

  Widget _interactionLens(
    int selected,
    int count,
    double progress,
    double lift,
  ) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedAlign(
        duration: _dragAlignment != null ? Duration.zero : _travelTime,
        curve: _travelCurve,
        alignment: AlignmentDirectional(
          _dragAlignment ?? (count == 1 ? 0 : -1 + 2 * selected / (count - 1)),
          0,
        ),
        child: FractionallySizedBox(
          widthFactor: 1 / count,
          heightFactor: 1,
          child: Transform.scale(
            scaleX: 1 + _heldWidthGrowth * lift,
            scaleY: 1 + _heldHeightGrowth * lift,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_pillRadius),
              child: LiquidGlassBatch.exclude(
                child: MornyeLiquidBackdrop(
                  borderRadius: BorderRadius.circular(_pillRadius),
                  clarity: 1,
                  interaction: true,
                  progress: progress,
                  blurSigma: 0,
                  // Bend only the bevel; the middle of each glyph stays clear.
                  refractionDepth: 0.10,
                  refractionWidth: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_pillRadius),
                      color: Colors.white.withValues(
                        alpha:
                            progress *
                            (Theme.of(context).brightness == Brightness.light
                                ? 0.24
                                : 0.08),
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6 * progress),
                        width: 0.75,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Paint only icons and labels with the sliding selection color. Badge fills
/// and counters can remain outside this widget and retain their own contrast.
class MornyeSelectionForeground extends StatefulWidget {
  const MornyeSelectionForeground({super.key, required this.child});

  final Widget child;

  @override
  State<MornyeSelectionForeground> createState() =>
      _MornyeSelectionForegroundState();
}

class _MornyeSelectionForegroundState extends State<MornyeSelectionForeground> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_SelectionForegroundScope>();
    if (scope == null) return widget.child;
    if (_program != scope.program) {
      _shader?.dispose();
      _program = scope.program;
      _shader = _program?.fragmentShader();
    }
    late Rect local;
    late double width;
    late double rowHeight;
    return _SelectionShaderMask(
      maskIntersects: (bounds) {
        // A transparent srcATop source leaves the foreground unchanged.
        if (scope.color.a == 0) return false;
        final row =
            scope.rowKey.currentContext!.findRenderObject()! as RenderBox;
        final box = context.findRenderObject()! as RenderBox;
        width = row.size.width / scope.count;
        rowHeight = row.size.height;
        final left = (scope.alignment + 1) * (row.size.width - width) / 2;
        final lens = Rect.fromCenter(
          center: Offset(left + width / 2, rowHeight / 2),
          width: width * scope.scaleX,
          height: rowHeight * scope.scaleY,
        );
        local = Rect.fromPoints(
          box.globalToLocal(row.localToGlobal(lens.topLeft)),
          box.globalToLocal(row.localToGlobal(lens.bottomRight)),
        );
        // Keep generous AA room, including inverse foreground scaling.
        final padX = 2 * math.max(1.0, local.width / width);
        final padY = 2 * math.max(1.0, local.height / rowHeight);
        return bounds.right >= local.left - padX &&
            bounds.left <= local.right + padX &&
            // The gradient fallback is vertically unbounded.
            (_shader == null ||
                (bounds.bottom >= local.top - padY &&
                    bounds.top <= local.bottom + padY));
      },
      shaderCallback: (bounds) {
        // Use the same rounded, expanding bounds as the glass, including the
        // inverse scale of each icon. A one-tab rectangular mask cuts through
        // the foreground before it reaches the held lens's curved edge.
        final shader = _shader;
        if (shader != null) {
          shader
            ..setFloat(0, local.left)
            ..setFloat(1, local.top)
            ..setFloat(2, local.width)
            ..setFloat(3, local.height)
            ..setFloat(4, local.width / width)
            ..setFloat(5, local.height / rowHeight)
            ..setFloat(6, math.min(_pillRadius, math.min(width, rowHeight) / 2))
            ..setFloat(7, scope.color.r)
            ..setFloat(8, scope.color.g)
            ..setFloat(9, scope.color.b)
            ..setFloat(10, scope.color.a);
          return shader;
        }
        return ui.Gradient.linear(
          Offset(local.left, 0),
          Offset(local.right, 0),
          [scope.color, scope.color],
          null,
          TileMode.decal,
        );
      },
      child: widget.child,
    );
  }
}

class _SelectionShaderMask extends ShaderMask {
  const _SelectionShaderMask({
    required this.maskIntersects,
    required super.shaderCallback,
    required super.child,
  }) : super(blendMode: BlendMode.srcATop);

  final bool Function(Rect) maskIntersects;

  @override
  RenderShaderMask createRenderObject(BuildContext context) =>
      _SelectionRenderShaderMask(
        maskIntersects: maskIntersects,
        shaderCallback: shaderCallback,
      );

  @override
  void updateRenderObject(BuildContext context, RenderShaderMask renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _SelectionRenderShaderMask).maskIntersects =
        maskIntersects;
  }
}

class _SelectionRenderShaderMask extends RenderShaderMask {
  _SelectionRenderShaderMask({
    required this.maskIntersects,
    required super.shaderCallback,
  }) : super(blendMode: BlendMode.srcATop);

  bool Function(Rect) maskIntersects;

  @override
  void paint(PaintingContext context, Offset offset) {
    final foreground = child;
    if (foreground != null && !maskIntersects(foreground.paintBounds)) {
      // Drop any layer retained from a previous intersecting frame.
      layer = null;
      context.paintChild(foreground, offset);
    } else {
      // The predicate prepared this paint's geometry for shaderCallback.
      super.paint(context, offset);
    }
  }
}

class _SelectionForegroundScope extends InheritedWidget {
  const _SelectionForegroundScope({
    required this.rowKey,
    required this.alignment,
    required this.count,
    required this.scaleX,
    required this.scaleY,
    required this.program,
    required this.color,
    required super.child,
  });

  final GlobalKey rowKey;
  final double alignment;
  final int count;
  final double scaleX;
  final double scaleY;
  final ui.FragmentProgram? program;
  final Color color;

  @override
  bool updateShouldNotify(_SelectionForegroundScope oldWidget) =>
      alignment != oldWidget.alignment ||
      count != oldWidget.count ||
      scaleX != oldWidget.scaleX ||
      scaleY != oldWidget.scaleY ||
      program != oldWidget.program ||
      color != oldWidget.color ||
      rowKey != oldWidget.rowKey;
}
