import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The fill and the thin light rim shared by the player's glass controls.
final kPlayerGlassFill = Colors.white.withValues(alpha: 0.07);
const kPlayerGlassRim = BorderSide(color: Color(0x3DFFFFFF));

/// A round glass button for the dark player, with a thin light rim. It dips
/// while pressed. With [frosted] it also blurs what is behind it, for the
/// buttons that sit on the cover.
class PlayerGlassButton extends StatefulWidget {
  const PlayerGlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.iconSize = 24,
    this.fill = 0.07,
    this.pressedScale = 0.85,
    this.frosted = false,
    this.color,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;

  /// Opacity of the white fill, when no [color] is given.
  final double fill;
  final double pressedScale;

  /// Blur what is behind the button.
  final bool frosted;
  final Color? color;
  final Color? foreground;

  @override
  State<PlayerGlassButton> createState() => _PlayerGlassButtonState();
}

class _PlayerGlassButtonState extends State<PlayerGlassButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  Widget _frost(Widget glass) => widget.frosted
      ? ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: glass,
          ),
        )
      : glass;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: widget.onTap != null,
        label: widget.label,
        excludeSemantics: true,
        child: Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed && !reduceMotion ? widget.pressedScale : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: _frost(
              Material(
                color:
                    widget.color ?? Colors.white.withValues(alpha: widget.fill),
                shape: const CircleBorder(side: kPlayerGlassRim),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: Icon(
                      widget.icon,
                      size: widget.iconSize,
                      color:
                          widget.foreground ??
                          Colors.white.withValues(alpha: 0.94),
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
}
