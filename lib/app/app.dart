import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/cover_accent.dart';
import '../core/theme/noc_theme.dart';
import '../features/settings/settings_controller.dart';
import 'app_shell.dart';

class NocTuneApp extends ConsumerWidget {
  const NocTuneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final cover = settings.accentFromCover
        ? ref.watch(coverAccentProvider)
        : (light: null, dark: null);
    return MaterialApp(
      title: 'NocTune',
      debugShowCheckedModeBanner: false,
      theme: buildNocTheme(
        Brightness.light,
        settings.accent,
        coverAccent: cover.light,
      ),
      darkTheme: buildNocTheme(
        Brightness.dark,
        settings.accent,
        coverAccent: cover.dark,
      ),
      themeMode: settings.themeMode,
      // Slow enough that the accent glides from one cover's colour to the next.
      themeAnimationDuration: const Duration(milliseconds: 450),
      themeAnimationCurve: Curves.easeInOut,
      home: const AppShell(),
    );
  }
}
