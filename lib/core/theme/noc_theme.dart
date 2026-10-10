import 'package:flutter/material.dart';

import 'cover_accent.dart';
import 'noc_palette.dart';

/// Builds the Material theme for one brightness and accent. A [coverAccent],
/// taken from the playing track's artwork, replaces the chosen accent.
ThemeData buildNocTheme(
  Brightness brightness,
  NocAccent accent, {
  Color? coverAccent,
}) {
  final base = brightness == Brightness.dark
      ? NocPalette.dark(accent)
      : NocPalette.light(accent);
  final palette = coverAccent == null
      ? base
      : base.copyWith(accent: coverAccent, onAccent: onAccentFor(coverAccent));

  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.accent,
        brightness: brightness,
      ).copyWith(
        primary: palette.accent,
        onPrimary: palette.onAccent,
        surface: palette.background,
        onSurface: palette.textPrimary,
        onSurfaceVariant: palette.textSecondary,
        outlineVariant: palette.glassBorder,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    extensions: [palette],
    textTheme: _textTheme(palette),
    splashFactory: InkSparkle.splashFactory,
    iconTheme: IconThemeData(color: palette.textPrimary),
    dividerTheme: DividerThemeData(color: palette.glassBorder, space: 1),
    // Shapes are left to the slider itself, which draws the current
    // Material track and bar-shaped handle.
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.textTertiary.withValues(alpha: 0.35),
      thumbColor: palette.accent,
      overlayColor: palette.accent.withValues(alpha: 0.16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.glassSolid,
      contentTextStyle: TextStyle(color: palette.textPrimary),
    ),
  );
}

// Tracking is set per size: display text is tightened as it grows, body stays
// near zero, and the small uppercase eyebrow labels are opened up.
TextTheme _textTheme(NocPalette p) {
  return TextTheme(
    displaySmall: TextStyle(
      fontSize: 38,
      height: 1.02,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.1,
      color: p.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontSize: 26,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: p.textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: p.textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: p.textPrimary,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: p.textPrimary,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: p.textPrimary),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: p.textSecondary),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: p.textSecondary),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: p.textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: p.textSecondary,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: p.textSecondary,
    ),
  );
}
