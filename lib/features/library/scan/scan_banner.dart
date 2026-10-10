import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/noc_palette.dart';
import '../../../core/widgets/glass_panel.dart';
import 'scan_controller.dart';

/// Shows what the library scan is doing: progress with a way to cancel, a
/// permission request, or an error with a retry. Takes no space when idle.
class ScanBanner extends ConsumerWidget {
  const ScanBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    final (String message, Widget? detail, Widget? action) = switch (state) {
      ScanIdle() => ('', null, null),
      ScanRunning(:final processed, :final total) => (
        total == 0
            ? 'Looking for music…'
            : 'Reading tracks · $processed of $total',
        LinearProgressIndicator(
          value: total == 0 ? null : processed / total,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
          color: context.noc.accent,
          backgroundColor: context.noc.glassBorder,
        ),
        TextButton(onPressed: controller.cancel, child: const Text('Cancel')),
      ),
      ScanNeedsPermission(:final permanentlyDenied) => (
        permanentlyDenied
            ? 'NocTune needs access to your music. Allow "Music and audio" '
                  'for NocTune in Settings.'
            : 'NocTune needs access to your music to build your library.',
        null,
        permanentlyDenied
            ? TextButton(
                onPressed: ref.read(libraryPermissionProvider).openSettings,
                child: const Text('Open Settings'),
              )
            : TextButton(
                onPressed: controller.scan,
                child: const Text('Allow'),
              ),
      ),
      ScanFailed(:final message) => (
        message,
        null,
        TextButton(onPressed: controller.scan, child: const Text('Try again')),
      ),
    };
    if (state is ScanIdle) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassPanel(
        blur: 0,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                // Announce prompts and errors, but not every progress tick.
                liveRegion: state is! ScanRunning,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: text.bodyMedium),
                    if (detail != null) ...[const SizedBox(height: 8), detail],
                  ],
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
