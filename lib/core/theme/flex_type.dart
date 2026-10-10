import 'package:flutter/painting.dart';

/// The app's type scale in Google Sans Flex, at its regular width and with no
/// rounding, so every screen is set in the same letterforms. The theme uses
/// the same family for everything that doesn't name a role here.
///
/// Tracking is set per size: the large display roles are tightened, body
/// and label roles are left as drawn.
///
/// Weight is set on the font's own axis, not with [TextStyle.fontWeight], so
/// the in-between weights below render as drawn instead of being rounded to
/// the nearest hundred or faked.
abstract final class FlexType {
  static const family = 'Google Sans Flex';

  /// A style of this family at any size, for text outside the fixed roles.
  static TextStyle custom({
    required double size,
    required double lineHeight,
    required double weight,
    double width = 100,
    double round = 0,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    letterSpacing: letterSpacing,
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
      FontVariation('ROND', round),
      FontVariation('opsz', size.clamp(6, 144).toDouble()),
      const FontVariation('GRAD', 0),
    ],
  );

  static final displaySmall = custom(
    size: 36,
    lineHeight: 44,
    weight: 700,
    letterSpacing: -0.6,
  );
  static final headlineSmall = custom(
    size: 24,
    lineHeight: 32,
    weight: 700,
    letterSpacing: -0.3,
  );
  static final titleLarge = custom(
    size: 22,
    lineHeight: 28,
    weight: 650,
    letterSpacing: -0.2,
  );
  static final titleMedium = custom(size: 16, lineHeight: 24, weight: 600);
  static final titleSmall = custom(size: 14, lineHeight: 20, weight: 560);
  static final bodyLarge = custom(size: 16, lineHeight: 24, weight: 430);
  static final bodyMedium = custom(size: 15, lineHeight: 22, weight: 420);
  static final bodySmall = custom(size: 13, lineHeight: 18, weight: 420);
  static final labelLarge = custom(size: 14, lineHeight: 20, weight: 620);
  static final labelMedium = custom(size: 12, lineHeight: 16, weight: 600);
  static final labelSmall = custom(size: 11, lineHeight: 16, weight: 600);
}
