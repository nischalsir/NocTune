import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scan_controller.dart';

/// The ways to get music into the library, offered on empty screens.
///
/// Android can scan the whole device. iOS apps can only see their own folder,
/// so there the route is importing files.
class AddMusicActions extends ConsumerWidget {
  const AddMusicActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scanControllerProvider.notifier);
    final busy = ref.watch(scanControllerProvider) is ScanRunning;
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (isAndroid)
          FilledButton.icon(
            onPressed: busy ? null : controller.scan,
            icon: const Icon(Icons.radar_rounded),
            label: const Text('Scan this device'),
          ),
        if (isAndroid)
          OutlinedButton.icon(
            onPressed: busy ? null : controller.importFiles,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import files'),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : controller.importFiles,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import files'),
          ),
      ],
    );
  }
}
