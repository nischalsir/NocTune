// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// Copyright (c) 2026 zarzet, MIT licence. See LICENSE in this folder.
// Changes for NocTune: imports, app-specific hooks, and the tab bar on glass,
// which is liquid_glass_easy's own bar over the frosted capsule: the
// selection rests as a flat pill and travels between tabs as a lens that
// refracts the capsule, on the package's spring.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'runtime_profile_provider.dart';
import 'mornye_theme.dart';
import 'mornye_selection_pill.dart';
import 'mornye_liquid_backdrop.dart';
import 'animated_badge.dart';

class MornyeSegmentedControl extends ConsumerWidget {
  const MornyeSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final height = MediaQuery.textScalerOf(context).scale(15) + 36;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: height,
        child: MornyeGlass.navigation(
          blurEnabled: ref.watch(mornyeBlurEnabledProvider),
          radius: height / 2,
          child: MornyeSelectionPill(
            liquidInteraction:
                ref.watch(mornyeLiquidGlassProvider) &&
                MornyeTheme.glassClarityOf(context) > 0.2,
            labels: labels,
            selectedIndex: selectedIndex,
            onChanged: onChanged,
            itemBuilder: (context, index, selected) => Center(
              child: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared material for panels, menus, dialogs and floating sheets.
class MornyeGlassPanel extends ConsumerWidget {
  const MornyeGlassPanel({
    super.key,
    required this.child,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.blurEnabled = true,
    this.highlightBorder = false,
  }) : _composedBackdrop = false;

  const MornyeGlassPanel.overlay({
    super.key,
    required this.child,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.tintOpacity = 0.78,
    this.tintColor,
    this.blurEnabled = true,
    this.highlightBorder = false,
  }) : strongTint = true,
       _composedBackdrop = true;

  final Widget child;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;
  final bool blurEnabled;
  final bool highlightBorder;
  final bool _composedBackdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = MornyeGlass.navigation(
      radius: radius,
      firstInGroup: firstInGroup,
      lastInGroup: lastInGroup,
      strongTint: strongTint,
      tintOpacity: tintOpacity,
      tintColor: tintColor,
      blurEnabled: blurEnabled && ref.watch(mornyeBlurEnabledProvider),
      highlightBorder: highlightBorder,
      // Tile ink must paint above the glass tint rather than beneath it.
      child: Material(type: MaterialType.transparency, child: child),
    );
    // One overlay gets its own key: the package composes blur and refraction
    // into one backdrop read, including while the route moves. Sharing that
    // key with the page or another overlapping menu would lose their glass.
    return _composedBackdrop ? LiquidGlassBatch(child: glass) : glass;
  }
}

/// Bounded glass: Impeller lenses refract a blurred backdrop, while frosted
/// surfaces share ordinary blur passes. Foreground content stays above glass.
class MornyeGlass extends ConsumerWidget {
  const MornyeGlass({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.highlightBorder = false,
    this.refractionDepth = 0.30,
  }) : firstInGroup = true,
       lastInGroup = true,
       samplesBackdrop = true;

  const MornyeGlass.navigation({
    super.key,
    required this.child,
    required this.blurEnabled,
    this.radius = 32,
    this.firstInGroup = true,
    this.lastInGroup = true,
    this.strongTint = false,
    this.tintOpacity,
    this.tintColor,
    this.samplesBackdrop = true,
    this.highlightBorder = false,
    this.refractionDepth = 0.30,
  });

  // Quantized and shared across surfaces. Avoid composed color filters and
  // rebuilding a Gaussian filter for each clarity-slider animation frame.
  static const _blurSigmas = [2.0, 3.0, 6.0, 16.0];
  static final _blurs = [
    for (final sigma in _blurSigmas)
      ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  ];

  final Widget child;
  final bool blurEnabled;
  final double radius;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool strongTint;
  final double? tintOpacity;
  final Color? tintColor;

  /// Paint the edge above the fill so tinted popovers retain a visible rim.
  final bool highlightBorder;
  final double refractionDepth;

  /// Plain-page surfaces keep their tint without filtering a uniform backdrop.
  final bool samplesBackdrop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final clarity = MornyeTheme.glassClarityOf(context);
    final level = ref.watch(mornyeGlassLevelProvider);
    final translucent =
        blurEnabled &&
        level != MornyeGlassLevel.flat &&
        clarity > 0 &&
        !MediaQuery.highContrastOf(context);
    final dark = scheme.brightness == Brightness.dark;
    final shape = BorderRadius.vertical(
      top: firstInGroup ? Radius.circular(radius) : Radius.zero,
      bottom: lastInGroup ? Radius.circular(radius) : Radius.zero,
    );
    final artworkTint = Theme.of(context)
        .extension<MornyeTheme>()
        ?.chromeSurface;
    var tintSource =
        tintColor ?? (dark ? scheme.surfaceContainerHigh : Colors.white);
    var opacity = tintOpacity ?? (strongTint ? 0.80 : 0.60);
    if (tintColor == null && artworkTint != null) {
      // The artwork color is already known; retain its hue with a richer tint
      // instead of a saturation filter over changing page content.
      final hsl = HSLColor.fromColor(scheme.surfaceContainerHigh);
      final coverTint = hsl
          .withSaturation((hsl.saturation * 1.6).clamp(0, 1))
          .toColor();
      tintSource = dark
          ? coverTint
          : Color.lerp(Colors.white, coverTint, 0.15)!;
      opacity = opacity.clamp(0.60, 1.0);
    }
    // Light glass needs a white veil over saturated or dark artwork.
    // Keep this in the existing fill so whitening adds no backdrop pass.
    var baseTint = tintSource.withValues(
      alpha: dark ? opacity * 0.82 : (opacity * 0.88).clamp(0.50, 1.0),
    );
    if (dark) {
      // Bound bright artwork with paint instead of filtering backdrop luma.
      baseTint = Color.alphaBlend(
        baseTint,
        Colors.black.withValues(alpha: 0.35),
      );
    }
    // Let the upper end of the clarity slider reveal more of the page. Keep
    // the tinted endpoint opaque and the single-pass blur budget unchanged.
    final tintStrength = (1 - clarity) * (1 - clarity);
    final tint = translucent
        ? Color.alphaBlend(
            scheme.surfaceContainerHigh.withValues(alpha: tintStrength),
            baseTint,
          )
        : scheme.surfaceContainerHigh;
    final insideGlass =
        context.dependOnInheritedWidgetOfExactType<_GlassBackdropScope>() !=
        null;
    // At low clarity the tint obscures almost all detail. In particular, 10%
    // must not suddenly enable backdrop sampling on a mid-range GPU.
    final blurThreshold = level == MornyeGlassLevel.frosted ? 0.5 : 0.2;
    final sampleBackdrop =
        translucent &&
        samplesBackdrop &&
        !insideGlass &&
        clarity > blurThreshold;
    final useLens =
        sampleBackdrop &&
        firstInGroup &&
        lastInGroup &&
        level == MornyeGlassLevel.liquid &&
        ImageFilter.isShaderFilterSupported;
    // Clear glass softens the backdrop less. Keep the mid-range fallback at
    // its small blur budget, and reuse these filters in the lens renderer too.
    final filterIndex = level == MornyeGlassLevel.frosted
        ? 1
        : clarity >= 0.9
        ? 0
        : clarity >= 0.6
        ? 2
        : 3;
    final clearFill = (dark ? const Color(0xff999999) : Colors.white)
        .withValues(alpha: dark ? 0.17 : 0.46);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: useLens && !strongTint
            ? Color.lerp(tint, clearFill, ((clarity - 0.2) / 0.8).clamp(0, 1))
            : tint,
        borderRadius: shape,
      ),
      // Child controls paint on this surface; never re-blur their parent.
      child: _GlassBackdropScope(child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: firstInGroup && lastInGroup
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.14 : 0.08),
                  blurRadius: 8,
                  blurStyle: BlurStyle.outer,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: _MornyeGlassRim(
          shape: shape,
          firstInGroup: firstInGroup,
          lastInGroup: lastInGroup,
          illuminated: translucent && (!useLens || highlightBorder),
          emphasized: highlightBorder,
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: useLens
              ? MornyeLiquidBackdrop(
                  borderRadius: shape,
                  clarity: clarity,
                  blurSigma: _blurSigmas[filterIndex],
                  refractionDepth: refractionDepth,
                  child: surface,
                )
              : sampleBackdrop
              ? BackdropFilter.grouped(
                  filter: _blurs[filterIndex],
                  child: surface,
                )
              : surface,
        ),
      ),
    );
  }
}

class _GlassBackdropScope extends InheritedWidget {
  const _GlassBackdropScope({required super.child});

  @override
  bool updateShouldNotify(_GlassBackdropScope oldWidget) => false;
}

/// Subtle edge definition without another offscreen layer or backdrop read.
class _MornyeGlassRim extends CustomPainter {
  const _MornyeGlassRim({
    required this.shape,
    required this.firstInGroup,
    required this.lastInGroup,
    required this.illuminated,
    required this.emphasized,
  });

  final BorderRadius shape;
  final bool firstInGroup;
  final bool lastInGroup;
  final bool illuminated;
  final bool emphasized;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final outline = shape.toRRect(
      Rect.fromLTRB(
        0,
        firstInGroup ? 0 : -2,
        size.width,
        lastInGroup ? size.height : size.height + 2,
      ),
    );
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRRect(
      outline.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        // A thin contact edge must not paint a shadow under the whole glass.
        ..color = Colors.black.withValues(alpha: 0.5),
    );
    if (illuminated) {
      canvas.drawRRect(
        outline.deflate(0.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = emphasized ? 1 : 0.6
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.14, 0.5, 0.86, 1],
            colors: [
              firstInGroup
                  ? Color(emphasized ? 0x88ffffff : 0x40ffffff)
                  : Colors.transparent,
              Color(emphasized ? 0x26ffffff : 0x0dffffff),
              const Color(0x0a000000),
              Color(emphasized ? 0x20ffffff : 0x0dffffff),
              lastInGroup
                  ? Color(emphasized ? 0x55ffffff : 0x26ffffff)
                  : Colors.transparent,
            ],
          ).createShader(bounds),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MornyeGlassRim oldDelegate) =>
      shape != oldDelegate.shape ||
      firstInGroup != oldDelegate.firstInGroup ||
      lastInGroup != oldDelegate.lastInGroup ||
      illuminated != oldDelegate.illuminated ||
      emphasized != oldDelegate.emphasized;
}

/// A searchable category uses the same material as the navigation capsule.
class MornyeFilterChip extends ConsumerWidget {
  const MornyeFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.blurEnabled = true,
    this.glass = true,
    this.tonal = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool blurEnabled;
  final bool glass;
  final bool tonal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final content = Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: !glass && !tonal
            ? Colors.transparent
            : selected
            ? scheme.primary.withValues(alpha: 0.12)
            : glass
            ? Colors.transparent
            : MornyeTheme.controlFill(context, enabled: onTap != null),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!glass) {
      return ClipRRect(borderRadius: BorderRadius.circular(24), child: content);
    }
    return MornyeGlass.navigation(
      radius: 24,
      blurEnabled: blurEnabled && ref.watch(mornyeBlurEnabledProvider),
      child: content,
    );
  }
}

class MornyeNavigationIcon extends StatelessWidget {
  const MornyeNavigationIcon({
    super.key,
    required this.icon,
    required this.badgeCount,
  });

  final IconData icon;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => AnimatedBadge(
    count: badgeCount,
    child: Badge(
      isLabelVisible: badgeCount > 0,
      label: Text('$badgeCount'),
      child: MornyeSelectionForeground(child: Icon(icon)),
    ),
  );
}

class MornyeTabBar extends StatelessWidget {
  const MornyeTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.blurEnabled,
    this.liquidGlass = true,
    this.hiddenIconIndices = const {},
    this.contentOpacity = const AlwaysStoppedAnimation(1),
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool blurEnabled;
  final bool liquidGlass;
  final Set<int> hiddenIconIndices;

  /// Fade only the foreground so the backdrop can keep sampling the page.
  final Animation<double> contentOpacity;

  /// The floating layout also supplies the coordinates for collapsing icons.
  static bool usesLiquidGlass(
    BuildContext context, {
    required bool blurEnabled,
    required bool liquidGlass,
  }) =>
      blurEnabled &&
      liquidGlass &&
      MornyeTheme.glassClarityOf(context) > 0 &&
      !MediaQuery.disableAnimationsOf(context) &&
      !MediaQuery.highContrastOf(context);

  /// NocTune: the bar on glass. The frosted capsule is a sibling beneath the
  /// package's tab bar, not its ancestor, so the travelling lens refracts
  /// the capsule's real pixels rather than a filtered copy of them.
  Widget _glassTabs(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        // Room above and below the capsule for the lens to lift and stretch
        // without being clipped.
        height: 80,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                height: 64,
                child: MornyeGlass.navigation(
                  blurEnabled: blurEnabled,
                  strongTint: true,
                  tintOpacity: MornyeTheme.navigationOpacity(context),
                  refractionDepth: 0.45,
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fill(
                // Fades the icons, labels and resting pill only: the
                // capsule keeps sampling the page while the bar folds.
                child: FadeTransition(
                  opacity: contentOpacity,
                  child: LiquidGlassTabBar.withImpeller(
                    width: constraints.maxWidth,
                    height: 64,
                    margin: const EdgeInsets.only(bottom: 8),
                    selectedIndex: selectedIndex,
                    onChanged: onSelected,
                    style: LiquidGlassTabBar.defaultStyle.copyWith(
                      // The capsule beneath supplies the rim, tint and blur;
                      // this one stays clear so the lens has icons to bend.
                      shape: const LiquidGlassShape.continuousRoundedRectangle(
                        cornerRadius: 32,
                        borderWidth: 0,
                        lightIntensity: 0,
                      ),
                      appearance: const LiquidGlassAppearance(),
                      refraction: const LiquidGlassRefraction(
                        distortion: 0,
                        chromaticAberration: 0,
                      ),
                    ),
                    itemStyle: LiquidGlassTabItemStyle(
                      selectedColor: scheme.primary,
                      unselectedColor: scheme.onSurface,
                      iconSize: 25,
                      labelFontSize: 11,
                      selectedFontWeight: FontWeight.w600,
                      unselectedFontWeight: FontWeight.w600,
                      iconLabelGap: 2,
                    ),
                    pillStyle: LiquidGlassTabPillStyle(
                      mode: LiquidGlassPillMode.impellerOnly,
                      color: scheme.onSurface.withValues(
                        alpha: scheme.brightness == Brightness.dark
                            ? 0.12
                            : 0.08,
                      ),
                      animated: true,
                      // One lens: the package's second, magnifying one
                      // under it is left out.
                      magnifierPill: const LiquidGlassTabMagnifierPillStyle(
                        enabled: false,
                      ),
                    ),
                    itemPadding: 6,
                    items: [
                      for (final (index, destination) in destinations.indexed)
                        LiquidGlassTabBarItem(
                          label: destination.label,
                          iconBuilder: (context, glyph) => Opacity(
                            opacity: hiddenIconIndices.contains(index) ? 0 : 1,
                            child: IconTheme(
                              data: IconThemeData(
                                size: glyph.size,
                                color: glyph.color,
                              ),
                              child: destination.icon,
                            ),
                          ),
                          labelBuilder: (context, label) => Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // The capsule's height is fixed, so the labels
                            // stop growing where they would no longer fit.
                            textScaler: MediaQuery.textScalerOf(context)
                                .clamp(maxScaleFactor: 1.5),
                            style: labelStyle?.copyWith(
                              fontSize: label.fontSize,
                              fontWeight: FontWeight.w600,
                              color: label.color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (usesLiquidGlass(
      context,
      blurEnabled: blurEnabled,
      liquidGlass: liquidGlass,
    )) {
      return _glassTabs(context);
    }
    // Without glass: a flat capsule whose flat pill slides between tabs.
    return MornyeSelectionPill(
      selectionColor: scheme.primary,
      maskItemForeground: false,
      labels: [for (final destination in destinations) destination.label],
      selectedIndex: selectedIndex,
      onChanged: onSelected,
      padding: const EdgeInsets.all(5),
      interactionBuilder: (context, progress, child) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            // Only the capsule projects forward. Icons, labels and touch
            // coordinates stay fixed, and collapse never fades the backdrop.
            child: Transform.scale(
              scaleX: 1 + 0.025 * progress,
              scaleY: 1 + 0.06 * progress,
              child: MornyeGlass.navigation(
                blurEnabled: blurEnabled,
                strongTint: true,
                tintOpacity: MornyeTheme.navigationOpacity(context),
                refractionDepth: 0.45 + 0.15 * progress,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // The selection lens can swell beyond the capsule's clip.
          FadeTransition(opacity: contentOpacity, child: child),
        ],
      ),
      itemBuilder: (context, index, selected) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(
                  size: 25,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
                child: Opacity(
                  opacity: hiddenIconIndices.contains(index) ? 0 : 1,
                  child: destinations[index].icon is MornyeNavigationIcon
                      ? destinations[index].icon
                      : MornyeSelectionForeground(
                          child: destinations[index].icon,
                        ),
                ),
              ),
              const SizedBox(height: 2),
              MornyeSelectionForeground(
                child: Text(
                  destinations[index].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
