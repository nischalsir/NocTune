import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/glass_panel.dart';
import '../library/duplicates_screen.dart';
import '../library/scan/scan_banner.dart';
import '../library/scan/scan_controller.dart';
import '../playback/audio_capabilities.dart';
import '../startup/startup_prompts.dart';
import 'settings_controller.dart';

/// Appearance, privacy and app information.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final version = ref.watch(installedVersionProvider).value;
    final atmosDecoder = ref.watch(deviceDecodesAtmosProvider).value;
    final updatesConfigured =
        ref.watch(updateServiceProvider).value?.isConfigured ?? false;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Settings', style: text.headlineSmall),
          const SizedBox(height: 20),
          _Section(
            title: 'APPEARANCE',
            children: [
              Text('Theme', style: text.titleSmall),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {settings.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (modes) =>
                    controller.setThemeMode(modes.single),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Match the cover art'),
                subtitle: const Text(
                  'The accent follows the artwork of the track that is playing',
                ),
                value: settings.accentFromCover,
                onChanged: controller.setAccentFromCover,
              ),
              const SizedBox(height: 8),
              Text(
                settings.accentFromCover
                    ? 'Accent when nothing is playing'
                    : 'Accent colour',
                style: text.titleSmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final accent in NocAccent.values)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: accent.onDark),
                      label: Text(accent.label),
                      selected: accent == settings.accent,
                      showCheckmark: false,
                      onSelected: (_) => controller.setAccent(accent),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'LIBRARY',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Rescan library'),
                subtitle: const Text(
                  'Looks for new, changed and removed files',
                ),
                onTap: ref.read(scanControllerProvider.notifier).scan,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('Find duplicates'),
                subtitle: const Text('Lists tracks stored more than once'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DuplicatesScreen(),
                  ),
                ),
              ),
              const ScanBanner(),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'AUDIO',
            children: [
              Text('Dolby Atmos', style: text.titleSmall),
              const SizedBox(height: 4),
              Text(switch (atmosDecoder) {
                true =>
                  'This device reports a Dolby Atmos decoder. Tracks that '
                      'are Atmos recordings are decoded by it and labelled '
                      'in the player.',
                false =>
                  'This device reports no Dolby Atmos decoder, so no track '
                      'is labelled as Atmos.',
                null => 'Checking what this device can decode…',
              }, style: text.bodyMedium),
              const SizedBox(height: 8),
              Text(
                'NocTune plays files as they are and applies no sound '
                'processing of its own. There is no Atmos switch: a track '
                'either is an Atmos recording or it is not.',
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'PRIVACY',
            children: [
              Text(
                'NocTune needs no account. Your music, file names and '
                'listening history never leave this device, and playback '
                'works with no connection at all.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                updatesConfigured
                    ? 'At launch the app fetches one small file to see '
                          'whether a newer version exists. It sends nothing '
                          'about you or your library.'
                    : 'This build makes no network requests: update checks '
                          'are not set up.',
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'ABOUT',
            children: [
              Text(
                version == null ? 'NocTune' : 'NocTune $version',
                style: text.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('Developed by Nischal Pandey', style: text.bodyMedium),
              Text('Instagram: @nischal_sir', style: text.bodyMedium),
              Text('nischalpandey.dev@gmail.com', style: text.bodyMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      blur: 0,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
