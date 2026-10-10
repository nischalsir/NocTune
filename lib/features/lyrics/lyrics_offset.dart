import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

const _keyPrefix = 'lyrics_offset_';

/// Furthest the lyrics of a track can be nudged either way.
const kMaxLyricsOffsetMs = 5000;

/// Per-track corrections to lyric timing, in milliseconds, saved on the
/// device. Positive shows lyrics earlier. The state holds the offsets
/// changed since launch; everything else is read from storage.
class LyricsOffsetController extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() => const {};

  void set(int trackId, int milliseconds) {
    final value = milliseconds.clamp(-kMaxLyricsOffsetMs, kMaxLyricsOffsetMs);
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == 0) {
      prefs.remove('$_keyPrefix$trackId');
    } else {
      prefs.setInt('$_keyPrefix$trackId', value);
    }
    state = {...state, trackId: value};
  }
}

final lyricsOffsetProvider =
    NotifierProvider<LyricsOffsetController, Map<int, int>>(
      LyricsOffsetController.new,
    );

/// The timing correction saved for one track, zero if there is none.
final lyricsOffsetOfProvider = Provider.family<int, int>(
  (ref, trackId) =>
      ref.watch(lyricsOffsetProvider)[trackId] ??
      ref.watch(sharedPreferencesProvider).getInt('$_keyPrefix$trackId') ??
      0,
);

/// Lets the user nudge when lyrics are highlighted for one track. The seek
/// bar and playback are unaffected.
Future<void> showLyricsOffsetDialog(BuildContext context, int trackId) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LyricsOffsetDialog(trackId: trackId),
    );

class _LyricsOffsetDialog extends ConsumerWidget {
  const _LyricsOffsetDialog({required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(lyricsOffsetOfProvider(trackId));
    final controller = ref.read(lyricsOffsetProvider.notifier);
    final text = Theme.of(context).textTheme;

    Widget step(String label, int delta) => Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        ),
        onPressed: () => controller.set(trackId, offset + delta),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );

    return AlertDialog(
      title: const Text('Lyrics sync offset'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Nudges the highlight when a file's timestamps run early or "
              'late. + shows lyrics early (fixes late lyrics), − delays '
              'them. The seek bar is unaffected.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                offset == 0
                    ? '0 ms (off)'
                    : '${offset > 0 ? '+' : ''}$offset ms',
                style: text.titleMedium,
              ),
            ),
            Slider(
              value: offset.toDouble(),
              min: -kMaxLyricsOffsetMs.toDouble(),
              max: kMaxLyricsOffsetMs.toDouble(),
              divisions: 200,
              semanticFormatterCallback: (value) => '${value.round()} ms',
              onChanged: (value) => controller.set(trackId, value.round()),
            ),
            Row(
              children: [
                step('−1s', -1000),
                const SizedBox(width: 4),
                step('−250ms', -250),
                const SizedBox(width: 4),
                step('+250ms', 250),
                const SizedBox(width: 4),
                step('+1s', 1000),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: offset == 0
                    ? null
                    : () => controller.set(trackId, 0),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Reset'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
