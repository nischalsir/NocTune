import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/theme/noc_palette.dart';
import 'audio_capabilities.dart';

/// The audio-format labels for the current track: LOSSLESS when the file is
/// verified lossless, Dolby Atmos when the file is Atmos content and this
/// device reports a decoder for it. They are information, not controls.
///
/// The row keeps the same height whether or not it shows anything, so the
/// transport below it never moves as tracks change.
class FormatBadges extends ConsumerWidget {
  const FormatBadges({super.key});

  static const height = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentId = ref.watch(currentTrackIdProvider);
    final track = ref.watch(currentTrackProvider).value;
    // While the next track's details are still loading, the provider still
    // holds the previous track. Never label one track with another's format.
    final codec = track != null && track.id == currentId ? track.codec : null;
    final badges = formatBadges(
      codec,
      deviceDecodesAtmos: ref.watch(deviceDecodesAtmosProvider).value ?? false,
    );
    final labels = [
      if (badges.atmos) 'Dolby Atmos',
      if (badges.lossless) 'LOSSLESS',
    ];

    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        child: Row(
          key: ValueKey(labels.join('|')),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (index, label) in labels.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              _Badge(label: label),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    return Semantics(
      label: 'Audio format: $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: palette.textSecondary.withValues(alpha: 0.45),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            // Fixed size: a badge is a mark, and must fit its row.
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
