import 'package:flutter/material.dart';

/// Accent colours the user can choose between in Settings.
enum NocAccent {
  red('Racing red', Color(0xFFE5182B), Color(0xFFC8101F)),
  ember('Ember', Color(0xFFF2642B), Color(0xFFC94A14)),
  blue('Cool blue', Color(0xFF4C8DF6), Color(0xFF1F63D6)),
  silver('Silver', Color(0xFFC7CCD6), Color(0xFF5A6170));

  const NocAccent(this.label, this.onDark, this.onLight);

  final String label;

  /// Accent used on dark surfaces.
  final Color onDark;

  /// Darker variant that keeps contrast on light surfaces.
  final Color onLight;
}

/// NocTune's colour roles. Widgets read these instead of raw colours so the
/// light theme, dark theme and the user's accent all flow through one place.
@immutable
class NocPalette extends ThemeExtension<NocPalette> {
  const NocPalette({
    required this.background,
    required this.backgroundDeep,
    required this.glass,
    required this.glassSolid,
    required this.glassChrome,
    required this.glassBorder,
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.coolBlue,
    required this.scrim,
  });

  factory NocPalette.dark(NocAccent accent) => NocPalette(
    background: const Color(0xFF07080C),
    backgroundDeep: const Color(0xFF0B1020),
    glass: const Color(0x14FFFFFF),
    glassSolid: const Color(0xFF151821),
    glassChrome: const Color(0xC40C0F17),
    glassBorder: const Color(0x1FFFFFFF),
    accent: accent.onDark,
    onAccent: accent == NocAccent.silver
        ? const Color(0xFF0B0D12)
        : Colors.white,
    textPrimary: const Color(0xFFF4F5F7),
    textSecondary: const Color(0xFFA9AFBC),
    textTertiary: const Color(0xFF737A88),
    coolBlue: const Color(0xFF6C8FD9),
    scrim: const Color(0xB3000000),
  );

  factory NocPalette.light(NocAccent accent) => NocPalette(
    background: const Color(0xFFF4F5F8),
    backgroundDeep: const Color(0xFFE6E9F0),
    glass: const Color(0xB3FFFFFF),
    glassSolid: Colors.white,
    glassChrome: const Color(0xE0FFFFFF),
    glassBorder: const Color(0x1A0B1020),
    accent: accent.onLight,
    onAccent: Colors.white,
    textPrimary: const Color(0xFF0E1116),
    textSecondary: const Color(0xFF4A5160),
    textTertiary: const Color(0xFF6E7684),
    coolBlue: const Color(0xFF2F5FC4),
    scrim: const Color(0x66000000),
  );

  /// Page base colour.
  final Color background;

  /// The colour the page gradient settles into (midnight navy in dark mode).
  final Color backgroundDeep;

  /// Translucent fill for glass panels.
  final Color glass;

  /// Opaque stand-in for [glass] when blur is unavailable or contrast is raised.
  final Color glassSolid;

  /// Denser fill for floating chrome (navigation, mini-player) that sits over
  /// arbitrary content, so its labels stay legible above bright artwork.
  final Color glassChrome;

  /// Hairline edge of glass panels.
  final Color glassBorder;

  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Restrained secondary accent for informational detail.
  final Color coolBlue;

  /// Dimming layer behind modal surfaces and over artwork.
  final Color scrim;

  @override
  NocPalette copyWith({Color? accent, Color? onAccent}) => NocPalette(
    background: background,
    backgroundDeep: backgroundDeep,
    glass: glass,
    glassSolid: glassSolid,
    glassChrome: glassChrome,
    glassBorder: glassBorder,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    coolBlue: coolBlue,
    scrim: scrim,
  );

  @override
  NocPalette lerp(NocPalette? other, double t) {
    if (other == null) return this;
    return NocPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundDeep: Color.lerp(backgroundDeep, other.backgroundDeep, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassSolid: Color.lerp(glassSolid, other.glassSolid, t)!,
      glassChrome: Color.lerp(glassChrome, other.glassChrome, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      coolBlue: Color.lerp(coolBlue, other.coolBlue, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

extension NocPaletteContext on BuildContext {
  NocPalette get noc => Theme.of(this).extension<NocPalette>()!;
}
