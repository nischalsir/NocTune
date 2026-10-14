import 'package:flutter/material.dart';

/// The player's own colours. It follows the app's light or dark theme: on
/// dark it draws in white over dark washes of the cover, on light in near
/// black over white ones.
extension PlayerColors on BuildContext {
  bool get _playerLight => Theme.of(this).brightness == Brightness.light;

  /// Text, icons and lines.
  Color get playerInk => _playerLight ? const Color(0xFF14161B) : Colors.white;

  /// The washes over the cover that keep everything on it readable.
  Color get playerShade => _playerLight ? Colors.white : Colors.black;

  /// The fill of a glass control. [fill] is how strong it is on the dark
  /// player; on the light one the glass is a frosted white, so the control
  /// still stands out from the pale backdrop.
  Color playerGlass([double fill = 0.07]) => _playerLight
      ? Colors.white.withValues(alpha: 0.5)
      : Colors.white.withValues(alpha: fill);

  /// The thin rim of a glass control.
  BorderSide get playerGlassRim => BorderSide(
    color: _playerLight ? const Color(0x24000000) : const Color(0x3DFFFFFF),
  );
}
