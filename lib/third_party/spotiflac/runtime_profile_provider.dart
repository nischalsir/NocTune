// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// Copyright (c) 2026 zarzet, MIT licence. See LICENSE in this folder.
// Changes for NocTune are limited to imports and app-specific hooks.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). UI uses it to skip expensive
/// effects like the shell's backdrop blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// Raw device capability decided by the startup runtime profile (overridden
/// in main.dart). Only the `high` tier enables blur by default.
final deviceSupportsBackdropBlurProvider = Provider<bool>((ref) => false);

/// Whether the GPU supports the higher blur budget and animated artwork /
/// lyric defocus. Glass controls themselves use the same lightweight renderer
/// on every tier. Overridden in main.dart.
final deviceSupportsLiquidGlassProvider = Provider<bool>((ref) => true);

/// Whether backdrop blur effects should render: the device default, or the
/// user's manual override from appearance settings.
final backdropBlurEnabledProvider = Provider<bool>((ref) {
  // NocTune has no manual "force blur" setting, so this is the device default.
  return ref.watch(deviceSupportsBackdropBlurProvider);
});

/// How much of Mornye's glass the device renders.
enum MornyeGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// Translucent surfaces over one backdrop blur; no shader passes.
  frosted,

  /// Impeller backdrop refraction, with a blur fallback on other renderers.
  liquid,
}

final mornyeGlassLevelProvider = Provider<MornyeGlassLevel>((ref) {
  final lowEnd = ref.watch(lowEndDeviceProvider);
  if (!lowEnd && ref.watch(deviceSupportsLiquidGlassProvider)) {
    return MornyeGlassLevel.liquid;
  }
  // The user's "always use blur effects" override restores the full material.
  if (ref.watch(backdropBlurEnabledProvider)) return MornyeGlassLevel.liquid;
  return lowEnd ? MornyeGlassLevel.flat : MornyeGlassLevel.frosted;
});

/// Backdrop blur for Mornye surfaces (frosted or liquid).
final mornyeBlurEnabledProvider = Provider<bool>(
  (ref) => ref.watch(mornyeGlassLevelProvider) != MornyeGlassLevel.flat,
);

/// Higher-quality glass and continuously filtered artwork / lyric effects.
final mornyeLiquidGlassProvider = Provider<bool>(
  (ref) => ref.watch(mornyeGlassLevelProvider) == MornyeGlassLevel.liquid,
);
