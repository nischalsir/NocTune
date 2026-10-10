import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/noc_palette.dart';
import '../../core/widgets/noc_dialog.dart';

/// Remembers, on the device, whether the first-run welcome has been seen.
class WelcomeStore {
  WelcomeStore(this._prefs);

  static const _key = 'welcome_seen';

  final SharedPreferences _prefs;

  /// True only until the welcome has been shown once. An ordinary restart
  /// keeps the stored flag, so it never counts as a new installation.
  bool get isPending => !(_prefs.getBool(_key) ?? false);

  Future<void> markSeen() => _prefs.setBool(_key, true);
}

/// The first-launch welcome. Either button simply enters the app: nothing is
/// requested here, and permissions are only asked for when the user chooses
/// to scan their music.
Future<void> showWelcomeDialog(BuildContext context) {
  return showNocDialog<void>(
    context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return NocDialogCard(
        title: 'Your music,\nfront and centre',
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Get started'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Maybe later'),
          ),
        ],
        children: [
          Text(
            'NocTune is an offline player for the music stored on this '
            'device.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 16),
          const _Point(
            icon: Icons.graphic_eq_rounded,
            text: 'Plays your local files, lossless FLAC included',
          ),
          const _Point(
            icon: Icons.queue_music_rounded,
            text: 'Playlists, favourites and a queue you can reorder',
          ),
          const _Point(
            icon: Icons.lock_outline_rounded,
            text: 'No account, and nothing leaves your device',
          ),
        ],
      );
    },
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.noc.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
