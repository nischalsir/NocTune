// The floating bottom bar: mini-player above a glass tab bar that folds away
// as the page is scrolled.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/noc_palette.dart';
import '../core/widgets/glass_panel.dart';
import '../features/playback/mini_player.dart';
import 'nav_icon_animations.dart';
import 'providers.dart';

/// One destination in the bar.
@immutable
class NocDestination {
  const NocDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.motion,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// How the icon animates in when the destination is selected.
  final NavIconMotion motion;
}

/// Whether the tabs are folded away.
///
/// Dragging a page down by a little folds them, to give the content room.
/// Dragging back up, reaching the top of the page, or choosing a destination
/// brings them back. Only drags the user is actually making count: sideways
/// lists, a fling coasting to a stop and overscroll bounce are ignored.
class ChromeController extends ValueNotifier<bool> {
  ChromeController() : super(false);

  /// How far, in logical pixels, a drag must travel to fold the tabs.
  static const _foldAfter = 32.0;

  /// How far a drag back towards the top must travel to unfold them.
  static const _unfoldAfter = 56.0;

  /// Within this distance of the top of a page the tabs are always shown.
  static const _topZone = 8.0;

  /// Distance dragged in the current direction: positive is down the page.
  double _travel = 0;

  void expand() {
    _travel = 0;
    value = false;
  }

  /// Feed this every scroll notification from the visible page. Always
  /// returns false, so the notification carries on to other listeners.
  bool handleScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification) {
      if (notification is ScrollEndNotification) _travel = 0;
      return false;
    }
    if (metrics.pixels <= metrics.minScrollExtent + _topZone) {
      expand();
      return false;
    }

    final step = notification.scrollDelta ?? 0;
    final byHand = notification.dragDetails != null;
    if (!byHand || metrics.outOfRange || step == 0) return false;

    // A change of direction starts the count again.
    if ((step > 0) != (_travel > 0)) _travel = 0;
    _travel += step;
    if (_travel >= _foldAfter) {
      value = true;
    } else if (_travel <= -_unfoldAfter) {
      value = false;
    }
    return false;
  }
}

/// Mini-player and tabs as one unit. When [collapsed], the tabs fold away and
/// the mini-player is flanked by two round glass buttons: the current
/// destination on the left and search on the right.
class NocBottomBar extends ConsumerStatefulWidget {
  const NocBottomBar({
    super.key,
    required this.collapsed,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.badgedIndex,
  });

  final bool collapsed;

  /// The last destination is treated as search.
  final List<NocDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Destination to mark with a dot, if any (work in progress there).
  final int? badgedIndex;

  @override
  ConsumerState<NocBottomBar> createState() => _NocBottomBarState();
}

class _NocBottomBarState extends ConsumerState<NocBottomBar>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: widget.collapsed ? 1 : 0,
  );
  late final _collapse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubicEmphasized,
  );

  void _syncCollapse() {
    final target = widget.collapsed ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
    } else {
      _controller.animateTo(target);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCollapse();
  }

  @override
  void didUpdateWidget(NocBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapsed != widget.collapsed) _syncCollapse();
  }

  @override
  void dispose() {
    _collapse.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = widget.destinations;
    final searchIndex = destinations.length - 1;
    // While search is open the left button offers the way back home.
    final leadingIndex = widget.selectedIndex == searchIndex
        ? 0
        : widget.selectedIndex;
    final hasPlayer = ref.watch(
      currentMediaItemProvider.select((item) => item.value != null),
    );
    // Built once and kept across the fold, so the mini-player keeps its
    // artwork, shared-element tag and swipe state while the tabs animate.
    final player = MiniPlayer(compact: widget.collapsed);
    final tabs = _GlassTabBar(
      destinations: destinations,
      selectedIndex: widget.selectedIndex,
      onSelected: widget.onSelected,
      badgedIndex: widget.badgedIndex,
    );

    return AnimatedBuilder(
      animation: _collapse,
      builder: (context, _) {
        final amount = _collapse.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasPlayer || amount > 0)
              Align(
                alignment: Alignment.bottomCenter,
                // With nothing playing the row only exists to carry the two
                // side buttons, so it grows in with the fold.
                heightFactor: hasPlayer ? 1 : amount,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8 * (1 - amount)),
                  child: Row(
                    children: [
                      _SideSlot(
                        amount: amount,
                        leading: true,
                        child: _SideButton(
                          icon: destinations[leadingIndex].selectedIcon,
                          label: destinations[leadingIndex].label,
                          highlighted: leadingIndex == widget.selectedIndex,
                          onTap: () => widget.onSelected(leadingIndex),
                        ),
                      ),
                      Expanded(child: player),
                      _SideSlot(
                        amount: amount,
                        leading: false,
                        child: _SideButton(
                          icon: destinations[searchIndex].icon,
                          label: destinations[searchIndex].label,
                          highlighted: widget.selectedIndex == searchIndex,
                          onTap: () => widget.onSelected(searchIndex),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // The tabs shrink away and fade as they go.
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1 - amount,
                child: IgnorePointer(
                  ignoring: amount > 0.5,
                  child: ExcludeSemantics(
                    excluding: amount > 0.5,
                    child: Opacity(opacity: 1 - amount, child: tabs),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Space beside the mini-player that opens up as the tabs fold, holding one
/// round button that scales in with it.
class _SideSlot extends StatelessWidget {
  const _SideSlot({
    required this.amount,
    required this.leading,
    required this.child,
  });

  /// 0 with the tabs showing, 1 when they are fully folded away.
  final double amount;
  final bool leading;
  final Widget child;

  static const _button = 52.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (_button + _gap) * amount,
      height: _button,
      child: amount == 0
          ? null
          : OverflowBox(
              minWidth: _button,
              maxWidth: _button,
              alignment: leading
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              child: IgnorePointer(
                ignoring: amount < 0.5,
                child: ExcludeSemantics(
                  excluding: amount < 0.5,
                  child: Transform.scale(scale: amount, child: child),
                ),
              ),
            ),
    );
  }
}

/// A round glass button shown beside the mini-player while the tabs are
/// folded away.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return GlassPanel(
      chrome: true,
      radius: 26,
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        color: highlighted ? palette.accent : palette.textPrimary,
        icon: Icon(icon, size: 25),
      ),
    );
  }
}

/// The glass tab bar. A tinted pill sits under the selected destination and
/// can be dragged sideways to another one.
class _GlassTabBar extends StatefulWidget {
  const _GlassTabBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.badgedIndex,
  });

  final List<NocDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int? badgedIndex;

  @override
  State<_GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<_GlassTabBar> {
  static const _inset = 6.0;

  /// Left edge of the pill while a finger is dragging it; null otherwise.
  double? _dragLeft;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    final count = widget.destinations.length;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Grows with the user's text size so labels are never clipped.
    final height = 46 + MediaQuery.textScalerOf(context).scale(18);

    return GlassPanel(
      chrome: true,
      radius: 30,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final tabWidth = (box.maxWidth - _inset * 2) / count;
            final restLeft = _inset + tabWidth * widget.selectedIndex;
            final maxLeft = _inset + tabWidth * (count - 1);

            int tabAt(double pillLeft) =>
                ((pillLeft - _inset + tabWidth / 2) / tabWidth).floor().clamp(
                  0,
                  count - 1,
                );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) =>
                  setState(() => _dragLeft = restLeft),
              onHorizontalDragUpdate: (details) => setState(
                () => _dragLeft = (_dragLeft! + details.delta.dx).clamp(
                  _inset,
                  maxLeft,
                ),
              ),
              onHorizontalDragEnd: (_) {
                final target = tabAt(_dragLeft!);
                setState(() => _dragLeft = null);
                widget.onSelected(target);
              },
              onHorizontalDragCancel: () => setState(() => _dragLeft = null),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    // Glued to the finger while dragging; eased otherwise.
                    duration: _dragLeft != null || reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    left: _dragLeft ?? restLeft,
                    top: _inset,
                    bottom: _inset,
                    width: tabWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _inset),
                    child: Row(
                      children: [
                        for (final (index, destination)
                            in widget.destinations.indexed)
                          Expanded(
                            child: _Tab(
                              destination: destination,
                              selected: index == widget.selectedIndex,
                              badged: index == widget.badgedIndex,
                              labelStyle: text.labelSmall!.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                              onTap: () => widget.onSelected(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.selected,
    required this.badged,
    required this.labelStyle,
    required this.onTap,
  });

  final NocDestination destination;
  final bool selected;
  final bool badged;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final color = selected ? palette.textPrimary : palette.textSecondary;
    final icon = selected
        ? AnimatedNavIcon(
            // A fresh key each time it becomes selected replays the motion.
            key: ValueKey(destination.label),
            motion: destination.motion,
            child: Icon(destination.selectedIcon, color: color),
          )
        : Icon(destination.icon, color: color);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: badged,
                smallSize: 8,
                backgroundColor: palette.accent,
                child: icon,
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
