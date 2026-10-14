import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../core/widgets/pill_button.dart';
import '../../third_party/spotiflac/mornye_chrome.dart';
import '../equalizer/equalizer_controller.dart';
import '../equalizer/equalizer_screen.dart';
import '../library/duplicates_screen.dart';
import '../library/scan/scan_banner.dart';
import '../library/scan/scan_controller.dart';
import '../playback/audio_capabilities.dart';
import '../startup/startup_prompts.dart';
import '../startup/update_dialog.dart';
import 'settings_controller.dart';

/// Whether Android lets NocTune show its playback notification. Null where
/// the question doesn't apply or can't be answered.
final _notificationAccessProvider = FutureProvider.autoDispose<bool?>((
  ref,
) async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return (await Permission.notification.status).isGranted;
  } on Exception {
    return null;
  }
});

/// The Settings destination. Every control here
/// changes something real and is remembered; rows that only inform say what
/// the app found rather than offering a switch that does nothing.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingForUpdate = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String url, {required String fallback}) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      opened = false;
    }
    if (!opened && mounted) _say(fallback);
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingForUpdate = true);
    final service = await ref.read(updateServiceProvider.future);
    final result = await service.checkNow();
    if (!mounted) return;
    setState(() => _checkingForUpdate = false);
    final update = result.update;
    if (update == null) {
      _say(
        result.checked
            ? 'NocTune is up to date.'
            : "Couldn't check for updates. Check your connection and try "
                  'again.',
      );
      return;
    }
    final choice = await showUpdateDialog(context, update);
    await applyUpdateChoice(service, update, choice);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showNocDialog<bool>(
      context,
      builder: (context) => NocDialogCard(
        title: 'Clear listening history?',
        actions: [
          PillButton(
            label: 'Clear history',
            destructive: true,
            onTap: () => Navigator.of(context).pop(true),
          ),
          PillButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
        children: [
          Text(
            'This resets every play count, the listening time and the '
            'recent, most played and top lists on the home screen. It '
            "can't be undone.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Your music, favourites and playlists are not touched.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(libraryRepositoryProvider).clearListeningHistory();
    if (mounted) _say('Listening history cleared.');
  }

  Future<void> _allowNotifications() async {
    final status = await Permission.notification.request();
    if (!status.isGranted) await openAppSettings();
    ref.invalidate(_notificationAccessProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    final version = ref.watch(installedVersionProvider).value;
    final atmosDecoder = ref.watch(deviceDecodesAtmosProvider).value;
    final updatesConfigured =
        ref.watch(updateServiceProvider).value?.isConfigured ?? false;
    final stats = ref.watch(libraryStatsProvider).value;
    final notifications = ref.watch(_notificationAccessProvider).value;
    final lyricsPercent = (settings.lyricsScale * 100).round();

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              // As the Library's title, on the same edge as the cards.
              Semantics(
                header: true,
                child: Text(
                  'Settings',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              _Group(
                title: 'Appearance',
                children: [
                  _Block(
                    icon: Icons.brightness_6_rounded,
                    title: 'Theme',
                    // The same glass selector as the navigation bar: it can
                    // be tapped or slid across.
                    child: MornyeSegmentedControl(
                      labels: const ['System', 'Light', 'Dark'],
                      selectedIndex: const [
                        ThemeMode.system,
                        ThemeMode.light,
                        ThemeMode.dark,
                      ].indexOf(settings.themeMode),
                      onChanged: (index) => controller.setThemeMode(
                        const [
                          ThemeMode.system,
                          ThemeMode.light,
                          ThemeMode.dark,
                        ][index],
                      ),
                    ),
                  ),
                  _SwitchTile(
                    icon: Icons.image_rounded,
                    title: 'Match the cover art',
                    subtitle:
                        'The accent follows the artwork of the track that '
                        'is playing',
                    value: settings.accentFromCover,
                    onChanged: controller.setAccentFromCover,
                  ),
                  _Block(
                    icon: Icons.palette_rounded,
                    title: settings.accentFromCover
                        ? 'Accent when nothing is playing'
                        : 'Accent colour',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final accent in NocAccent.values)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: accent.onDark,
                            ),
                            label: Text(accent.label),
                            selected: accent == settings.accent,
                            showCheckmark: false,
                            onSelected: (_) => controller.setAccent(accent),
                          ),
                      ],
                    ),
                  ),
                  _Block(
                    icon: Icons.blur_on_rounded,
                    title: 'Navigation bar glass',
                    child: Column(
                      children: [
                        Slider(
                          // The track starts and ends with the text.
                          padding: EdgeInsets.zero,
                          value: settings.navigationGlassClarity,
                          min: AppSettings.minGlassClarity,
                          divisions: 15,
                          semanticFormatterCallback: (value) =>
                              '${(value * 100).round()} percent clear',
                          onChanged: controller.setNavigationGlassClarity,
                        ),
                        // Under the slider, so large text has room.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Frosted',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Clear',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _SwitchTile(
                    icon: Icons.unfold_less_rounded,
                    title: 'Fold the navigation bar',
                    subtitle:
                        'Tucks the tabs away while you scroll down a page',
                    value: settings.foldNavigationOnScroll,
                    onChanged: controller.setFoldNavigationOnScroll,
                  ),
                ],
              ),

              _Group(
                title: 'Playback',
                children: [
                  _SwitchTile(
                    icon: Icons.waves_rounded,
                    title: 'Wave seek bar',
                    subtitle:
                        'The seek bar in the player moves like a wave while '
                        'music plays. Off, it is a plain thick bar.',
                    value: settings.waveSeekBar,
                    onChanged: controller.setWaveSeekBar,
                  ),
                ],
              ),

              _Group(
                title: 'Lyrics',
                children: [
                  _Block(
                    icon: Icons.format_size_rounded,
                    title: 'Text size',
                    trailing: Text('$lyricsPercent%', style: text.titleSmall),
                    child: Row(
                      children: [
                        Expanded(
                          child: Slider(
                            padding: EdgeInsets.zero,
                            value: settings.lyricsScale,
                            min: SettingsController.minLyricsScale,
                            max: SettingsController.maxLyricsScale,
                            divisions: 16,
                            label: '$lyricsPercent%',
                            semanticFormatterCallback: (value) =>
                                '${(value * 100).round()} percent',
                            onChanged: controller.setLyricsScale,
                          ),
                        ),
                        TextButton(
                          onPressed: settings.lyricsScale == 1
                              ? null
                              : () => controller.setLyricsScale(1),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                  const _Tile(
                    leading: _TileIcon(Icons.lyrics_rounded),
                    title: Text('Where lyrics come from'),
                    subtitle: Text(
                      'A file you import, an .lrc file beside the track, '
                      'or lyrics stored inside the audio file. Nothing is '
                      'downloaded.',
                    ),
                  ),
                ],
              ),

              _Group(
                title: 'Audio',
                children: [
                  _Tile(
                    leading: const _TileIcon(Icons.surround_sound_rounded),
                    title: const Text('Dolby Atmos'),
                    subtitle: Text(switch (atmosDecoder) {
                      true =>
                        'This device reports a Dolby Atmos decoder. '
                            'Tracks that are Atmos recordings are decoded '
                            'by it and labelled in the player.',
                      false =>
                        'This device reports no Dolby Atmos decoder, so '
                            'no track is labelled as Atmos.',
                      null => 'Checking what this device can decode…',
                    }),
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.graphic_eq_rounded),
                    title: const Text('Equaliser'),
                    subtitle: Text(ref.watch(equalizerProvider).summary),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EqualizerScreen(),
                      ),
                    ),
                  ),
                ],
              ),

              if (notifications != null)
                _Group(
                  title: 'Notification',
                  children: [
                    _Tile(
                      leading: const _TileIcon(Icons.notifications_rounded),
                      title: const Text('Playback notification'),
                      subtitle: Text(
                        notifications
                            ? 'Allowed. Playback controls appear in the '
                                  'notification shade and on the lock '
                                  'screen.'
                            : 'Off. Music still plays in the background, '
                                  'but without controls in the '
                                  'notification shade.',
                      ),
                      trailing: notifications
                          ? null
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: notifications ? null : _allowNotifications,
                    ),
                  ],
                ),

              _Group(
                title: 'Library',
                children: [
                  if (stats != null)
                    _Tile(
                      leading: const _TileIcon(Icons.library_music_rounded),
                      title: Text(
                        '${formatCount(stats.trackCount)} tracks · '
                        '${formatCount(stats.albumCount)} albums · '
                        '${formatCount(stats.artistCount)} artists',
                      ),
                      subtitle: Text(
                        '${formatLongDuration(stats.totalDuration)} of '
                        'music on this device',
                      ),
                    ),
                  _Tile(
                    leading: const _TileIcon(Icons.refresh_rounded),
                    title: const Text('Rescan library'),
                    subtitle: const Text(
                      'Looks for new, changed and removed files',
                    ),
                    onTap: ref.read(scanControllerProvider.notifier).scan,
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.copy_all_rounded),
                    title: const Text('Find duplicates'),
                    subtitle: const Text('Lists tracks stored more than once'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DuplicatesScreen(),
                      ),
                    ),
                  ),
                  _Tile(
                    leading: _TileIcon(
                      Icons.history_toggle_off_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Clear listening history'),
                    subtitle: const Text(
                      'Resets play counts and the home screen lists',
                    ),
                    onTap: _clearHistory,
                  ),
                  const ScanBanner(),
                ],
              ),

              _Group(
                title: 'Privacy',
                children: [
                  const _Tile(
                    leading: _TileIcon(Icons.lock_rounded),
                    title: Text('Everything stays on this device'),
                    subtitle: Text(
                      'No account. Your music, file names, lyrics and '
                      'listening history are never uploaded, and playback '
                      'works with no connection at all.',
                    ),
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.cloud_off_rounded),
                    title: const Text('Network use'),
                    subtitle: Text(
                      updatesConfigured
                          ? 'Only the update check: one small file is '
                                'fetched to see whether a newer version '
                                'exists. It sends nothing about you or '
                                'your library.'
                          : 'None. This build makes no network requests: '
                                'update checks are not set up.',
                    ),
                  ),
                ],
              ),

              _Group(
                title: 'About',
                children: [
                  _Tile(
                    leading: const _TileIcon(Icons.info_rounded),
                    title: const Text('NocTune'),
                    subtitle: Text(
                      version == null
                          ? 'Reading the version…'
                          : 'Version ${version.label} '
                                '(build ${version.build})',
                    ),
                  ),
                  if (updatesConfigured)
                    _Tile(
                      leading: const _TileIcon(Icons.system_update_rounded),
                      title: const Text('Check for updates'),
                      subtitle: Text(
                        _checkingForUpdate
                            ? 'Checking…'
                            : 'Looks for a newer release now',
                      ),
                      enabled: !_checkingForUpdate,
                      onTap: _checkForUpdate,
                    ),
                  _Tile(
                    leading: const _TileIcon(Icons.description_rounded),
                    title: const Text('Open-source licences'),
                    subtitle: const Text(
                      'The open-source software and typefaces NocTune '
                      'includes, with their licences',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'NocTune',
                      applicationVersion: version?.toString(),
                      applicationLegalese: '© 2026 Nischal Pandey',
                    ),
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.code_rounded),
                    title: const Text('Source code'),
                    subtitle: const Text('github.com/nischalsir/NocTune'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _open(
                      'https://github.com/nischalsir/NocTune',
                      fallback: 'github.com/nischalsir/NocTune',
                    ),
                  ),
                  const _Tile(
                    leading: _TileIcon(Icons.person_rounded),
                    title: Text('Developed by Nischal Pandey'),
                    subtitle: Text(
                      'Designed and built as a private, offline player for '
                      'the music on your device. No account, no ads, and '
                      'nothing is uploaded.',
                    ),
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.camera_alt_rounded),
                    title: const Text('Instagram'),
                    subtitle: const Text('@nischal_sir'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _open(
                      'https://instagram.com/nischal_sir',
                      fallback: 'Instagram: @nischal_sir',
                    ),
                  ),
                  _Tile(
                    leading: const _TileIcon(Icons.mail_rounded),
                    title: const Text('Email'),
                    subtitle: const Text('nischalpandey.dev@gmail.com'),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _open(
                      'mailto:nischalpandey.dev@gmail.com',
                      fallback: 'nischalpandey.dev@gmail.com',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card holding related settings, its rows separated by hairlines.
/// A setting that is on or off. Its switch moves the way an iOS one does:
/// the thumb stretches under the finger and can be dragged across.
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // Read out as one switch with its title, not a row and a switch.
    return MergeSemantics(
      child: _Tile(
        leading: _TileIcon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => onChanged(!value),
        trailing: CupertinoSwitch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// One row of a card: its icon, its title with a line or two under it, and
/// a switch or an arrow at the end. Laid out as [_Block] is: the title
/// starts level with the top of the icon, and the control sits on the
/// title's line, whatever is under it.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: text.bodyLarge,
                  textHeightBehavior: _titleHeight,
                  child: title,
                ),
                if (subtitle != null)
                  DefaultTextStyle.merge(
                    style: text.bodyMedium?.copyWith(
                      color: context.noc.textSecondary,
                    ),
                    child: subtitle,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            _OnTitleLine(child: trailing),
          ],
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(onTap: enabled ? onTap : null, child: row),
    );
  }
}

// A row's title starts right at the top of its icon: no space above its
// first line, so the tops of the letters are level with the icon's tile.
const _titleHeight = TextHeightBehavior(applyHeightToFirstAscent: false);

/// A switch, an arrow or a figure at the end of a row, centred on the
/// title's line rather than on the whole row.
class _OnTitleLine extends StatelessWidget {
  const _OnTitleLine({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // As wide as the control; as tall as the line, the control spilling
    // evenly above and below it.
    return IntrinsicWidth(
      child: SizedBox(
        height: 20,
        child: OverflowBox(maxHeight: double.infinity, child: child),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          Material(
            color: palette.glass,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: BorderSide(color: palette.glassBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, child) in children.indexed) ...[
                  if (index > 0 && child is! ScanBanner)
                    Divider(height: 1, indent: 72, color: palette.glassBorder),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting whose control needs a row of its own under its title.
class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TileIcon(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textHeightBehavior: _titleHeight,
                      ),
                    ),
                    if (trailing != null) _OnTitleLine(child: trailing),
                  ],
                ),
                const SizedBox(height: 10),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The icon at the start of a row, on a soft tinted tile.
class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.noc.accent;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}
