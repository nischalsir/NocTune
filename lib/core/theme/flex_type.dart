import 'package:flutter/painting.dart';

/// The type scale of the home feed and the lyrics view: Google Sans Flex,
/// with its weight, width, roundness and optical-size axes set per role.
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
    weight: 720,
    width: 118,
    round: 38,
    letterSpacing: -0.6,
  );
  static final headlineSmall = custom(
    size: 24,
    lineHeight: 32,
    weight: 760,
    width: 116,
    round: 36,
    letterSpacing: -0.3,
  );
  static final titleLarge = custom(
    size: 22,
    lineHeight: 28,
    weight: 640,
    width: 110,
    round: 30,
    letterSpacing: -0.2,
  );
  static final titleMedium = custom(
    size: 16,
    lineHeight: 24,
    weight: 600,
    width: 106,
    round: 28,
  );
  static final titleSmall = custom(
    size: 14,
    lineHeight: 20,
    weight: 580,
    width: 105,
    round: 26,
  );
  static final bodyLarge = custom(
    size: 16,
    lineHeight: 24,
    weight: 440,
    width: 102,
    round: 18,
  );
  static final bodyMedium = custom(
    size: 15,
    lineHeight: 22,
    weight: 430,
    width: 102,
    round: 18,
  );
  static final bodySmall = custom(
    size: 13,
    lineHeight: 18,
    weight: 420,
    round: 16,
  );
  static final labelLarge = custom(
    size: 14,
    lineHeight: 20,
    weight: 680,
    width: 108,
    round: 46,
  );
  static final labelMedium = custom(
    size: 12,
    lineHeight: 16,
    weight: 660,
    width: 108,
    round: 44,
  );
  static final labelSmall = custom(
    size: 11,
    lineHeight: 16,
    weight: 660,
    width: 108,
    round: 44,
  );
}
