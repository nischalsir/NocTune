import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.accent,
    required this.accentFromCover,
    this.lyricsScale = 1,
    this.foldNavigationOnScroll = true,
    this.waveSeekBar = true,
    this.navigationGlassClarity = defaultGlassClarity,
  });

  final ThemeMode themeMode;

  /// The accent used when no cover colour applies.
  final NocAccent accent;

  /// Whether the accent follows the cover art of the track that is playing.
  final bool accentFromCover;

  /// Multiplier applied to the lyrics text size.
  final double lyricsScale;

  /// Whether the navigation bar folds away while a page is scrolled down.
  final bool foldNavigationOnScroll;

  /// Whether the player's seek bar is the animated wave rather than the
  /// plain thick bar.
  final bool waveSeekBar;

  /// How clear the navigation bar's glass is, from 0.25 (frosted: what is
  /// behind it is a soft blur) to 1 (clear: it shows through).
  final double navigationGlassClarity;

  /// Frosted enough that list text behind the bar doesn't compete with its
  /// labels, clear enough to still read as glass.
  static const defaultGlassClarity = 0.55;
  static const minGlassClarity = 0.25;

  AppSettings copyWith({
    ThemeMode? themeMode,
    NocAccent? accent,
    bool? accentFromCover,
    double? lyricsScale,
    bool? foldNavigationOnScroll,
    bool? waveSeekBar,
    double? navigationGlassClarity,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    accentFromCover: accentFromCover ?? this.accentFromCover,
    lyricsScale: lyricsScale ?? this.lyricsScale,
    foldNavigationOnScroll:
        foldNavigationOnScroll ?? this.foldNavigationOnScroll,
    waveSeekBar: waveSeekBar ?? this.waveSeekBar,
    navigationGlassClarity:
        navigationGlassClarity ?? this.navigationGlassClarity,
  );
}

/// User preferences, persisted on the device.
class SettingsController extends Notifier<AppSettings> {
  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent';
  static const _coverAccentKey = 'accent_from_cover';
  static const _lyricsScaleKey = 'lyrics_scale';
  static const _foldNavigationKey = 'fold_navigation_on_scroll';
  static const _waveSeekBarKey = 'wave_seek_bar';
  static const _glassClarityKey = 'navigation_glass_clarity';

  /// Smallest and largest lyrics text multipliers offered.
  static const minLyricsScale = 0.7;
  static const maxLyricsScale = 1.5;

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      // Dark is the default: it is the look the app is designed around.
      themeMode:
          ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ??
          ThemeMode.dark,
      accent:
          NocAccent.values.asNameMap()[prefs.getString(_accentKey)] ??
          NocAccent.red,
      accentFromCover: prefs.getBool(_coverAccentKey) ?? true,
      lyricsScale: (prefs.getDouble(_lyricsScaleKey) ?? 1)
          .clamp(minLyricsScale, maxLyricsScale)
          .toDouble(),
      foldNavigationOnScroll: prefs.getBool(_foldNavigationKey) ?? true,
      waveSeekBar: prefs.getBool(_waveSeekBarKey) ?? true,
      navigationGlassClarity:
          (prefs.getDouble(_glassClarityKey) ?? AppSettings.defaultGlassClarity)
              .clamp(AppSettings.minGlassClarity, 1.0)
              .toDouble(),
    );
  }

  void setThemeMode(ThemeMode mode) {
    ref.read(sharedPreferencesProvider).setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  void setAccent(NocAccent accent) {
    ref.read(sharedPreferencesProvider).setString(_accentKey, accent.name);
    state = state.copyWith(accent: accent);
  }

  /// Sets the lyrics text multiplier, kept within the limits.
  void setLyricsScale(double value) {
    final scale = value.clamp(minLyricsScale, maxLyricsScale).toDouble();
    ref.read(sharedPreferencesProvider).setDouble(_lyricsScaleKey, scale);
    state = state.copyWith(lyricsScale: scale);
  }

  void setNavigationGlassClarity(double value) {
    final clarity = value.clamp(AppSettings.minGlassClarity, 1.0).toDouble();
    ref.read(sharedPreferencesProvider).setDouble(_glassClarityKey, clarity);
    state = state.copyWith(navigationGlassClarity: clarity);
  }

  void setWaveSeekBar(bool enabled) {
    ref.read(sharedPreferencesProvider).setBool(_waveSeekBarKey, enabled);
    state = state.copyWith(waveSeekBar: enabled);
  }

  void setFoldNavigationOnScroll(bool enabled) {
    ref.read(sharedPreferencesProvider).setBool(_foldNavigationKey, enabled);
    state = state.copyWith(foldNavigationOnScroll: enabled);
  }

  void setAccentFromCover(bool enabled) {
    ref.read(sharedPreferencesProvider).setBool(_coverAccentKey, enabled);
    state = state.copyWith(accentFromCover: enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
