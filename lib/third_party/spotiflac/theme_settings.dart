// Copied from SpotiFLAC-Mobile (https://github.com/zarzet/SpotiFLAC-Mobile),
// Copyright (c) 2026 zarzet, MIT licence. See LICENSE in this folder.
// Changes for NocTune are limited to imports and app-specific hooks.

import 'package:flutter/material.dart';

const String kThemeModeKey = 'theme_mode';
const String kUseDynamicColorKey = 'use_dynamic_color';
const String kSeedColorKey = 'seed_color';
const String kUseAmoledKey = 'use_amoled';
const String kThemeStyleKey = 'theme_style';
const String kMornyeAccentKey = 'mornye_accent';
const String kUseSystemFontKey = 'use_system_font';
const String kMornyeGlassClarityKey = 'mornye_glass_clarity';
const double kDefaultMornyeGlassClarity = 0.75;

double normalizeMornyeGlassClarity(num? value) =>
    value != null && value.isFinite
    ? value.toDouble().clamp(0.0, 1.0)
    : kDefaultMornyeGlassClarity;

enum AppThemeStyle { material, mornye }

enum MornyeAccent { red, orange, green, teal, blue, purple, pink }

MornyeAccent mornyeAccentFromString(String? value) =>
    MornyeAccent.values.firstWhere(
      (accent) => accent.name == value,
      orElse: () => MornyeAccent.red,
    );

AppThemeStyle themeStyleFromString(String? value) =>
    AppThemeStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => AppThemeStyle.material,
    );

/// Default Spotify green color for fallback
const int kDefaultSeedColor = 0xFF1DB954;

class ThemeSettings {
  final ThemeMode themeMode;
  final bool useDynamicColor;
  final int seedColorValue;
  final bool useAmoled;
  final AppThemeStyle style;
  final MornyeAccent mornyeAccent;
  final bool useSystemFont;
  final double mornyeGlassClarity;

  const ThemeSettings({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = true,
    this.seedColorValue = kDefaultSeedColor,
    this.useAmoled = false,
    this.style = AppThemeStyle.material,
    this.mornyeAccent = MornyeAccent.red,
    this.useSystemFont = false,
    this.mornyeGlassClarity = kDefaultMornyeGlassClarity,
  });

  Color get seedColor => Color(seedColorValue);

  ThemeSettings copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    int? seedColorValue,
    bool? useAmoled,
    AppThemeStyle? style,
    MornyeAccent? mornyeAccent,
    bool? useSystemFont,
    double? mornyeGlassClarity,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      useAmoled: useAmoled ?? this.useAmoled,
      style: style ?? this.style,
      mornyeAccent: mornyeAccent ?? this.mornyeAccent,
      useSystemFont: useSystemFont ?? this.useSystemFont,
      mornyeGlassClarity: normalizeMornyeGlassClarity(
        mornyeGlassClarity ?? this.mornyeGlassClarity,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    kThemeModeKey: themeMode.name,
    kUseDynamicColorKey: useDynamicColor,
    kSeedColorKey: seedColorValue,
    kUseAmoledKey: useAmoled,
    kThemeStyleKey: style.name,
    kMornyeAccentKey: mornyeAccent.name,
    kUseSystemFontKey: useSystemFont,
    kMornyeGlassClarityKey: mornyeGlassClarity,
  };

  factory ThemeSettings.fromJson(Map<String, dynamic> json) {
    return ThemeSettings(
      themeMode: themeModeFromString(json[kThemeModeKey] as String?),
      useDynamicColor: json[kUseDynamicColorKey] as bool? ?? true,
      seedColorValue: json[kSeedColorKey] as int? ?? kDefaultSeedColor,
      useAmoled: json[kUseAmoledKey] as bool? ?? false,
      style: themeStyleFromString(json[kThemeStyleKey] as String?),
      mornyeAccent: mornyeAccentFromString(json[kMornyeAccentKey] as String?),
      useSystemFont: json[kUseSystemFontKey] as bool? ?? false,
      mornyeGlassClarity: normalizeMornyeGlassClarity(
        json[kMornyeGlassClarityKey] as num?,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.themeMode == themeMode &&
        other.useDynamicColor == useDynamicColor &&
        other.seedColorValue == seedColorValue &&
        other.useAmoled == useAmoled &&
        other.style == style &&
        other.mornyeAccent == mornyeAccent &&
        other.useSystemFont == useSystemFont &&
        other.mornyeGlassClarity == mornyeGlassClarity;
  }

  @override
  int get hashCode =>
      themeMode.hashCode ^
      useDynamicColor.hashCode ^
      seedColorValue.hashCode ^
      useAmoled.hashCode ^
      style.hashCode ^
      mornyeAccent.hashCode ^
      useSystemFont.hashCode ^
      mornyeGlassClarity.hashCode;
}

ThemeMode themeModeFromString(String? value) {
  if (value == null) return ThemeMode.system;
  return ThemeMode.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ThemeMode.system,
  );
}
