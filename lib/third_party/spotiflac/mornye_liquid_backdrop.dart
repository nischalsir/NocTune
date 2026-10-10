// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// Copyright (c) 2026 zarzet, MIT licence. See LICENSE in this folder.
// Changes for NocTune are limited to imports and app-specific hooks.

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// A bounded package lens without a captured-screen view or a touch ticker.
class MornyeLiquidBackdrop extends StatelessWidget {
  const MornyeLiquidBackdrop({
    super.key,
    required this.borderRadius,
    required this.clarity,
    required this.blurSigma,
    required this.child,
    this.interaction = false,
    this.progress = 1,
    this.refractionDepth = 0.30,
    this.refractionWidth = 20,
  });

  final BorderRadius borderRadius;
  final double clarity;
  final double blurSigma;
  final Widget child;
  final bool interaction;
  final double progress;
  final double refractionDepth;
  final double refractionWidth;

  @override
  Widget build(BuildContext context) {
    if (interaction && progress <= 0) return child;
    final effect = interaction ? progress : 1.0;
    return LiquidGlassLens(
      style: LiquidGlassStyle(
        shape: LiquidGlassShape.roundedRectangle(
          cornerRadius: borderRadius.topLeft.x,
          borderWidth: 0.75,
          lightDirection: 0,
          lightIntensity: 0.25 * effect,
          lightColor: Colors.white,
          borderType: const OpticalBorder(
            ambientIntensity: 0.05,
            lightSpread: 0.2,
          ),
        ),
        appearance: LiquidGlassAppearance(
          blur: LiquidGlassBlur(sigmaX: blurSigma, sigmaY: blurSigma),
        ),
        // Translate Figma percentages into this package's optical controls.
        // Keep color separation subtle instead of copying its contrast demo.
        refraction: LiquidGlassRefraction(
          refractionType: OpticalRefraction(
            refraction: 1.7,
            depth: refractionDepth * effect,
            refractionWidth: refractionWidth,
          ),
          chromaticAberration: 0.002 * clarity * effect,
        ),
      ),
      child: child,
    );
  }
}
