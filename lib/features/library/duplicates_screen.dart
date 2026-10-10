import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio_format.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/noc_backdrop.dart';

/// Lists tracks that appear to be stored more than once. It only reports
/// them: NocTune never deletes or changes music files.
class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Duplicates'),
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: NocBackdrop(
        child: SafeArea(
          child: ref
              .watch(duplicatesProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: "Couldn't check for duplicates",
                  message: '$error',
                ),
                data: (sets) {
                  if (sets.isEmpty) {
                    return const EmptyState(
                      icon: Icons.done_all_rounded,
                      title: 'No duplicates found',
                      message:
                          'No two tracks share a title, artist and length.',
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Text(
                        'These tracks share a title, artist and length. '
                        'NocTune never deletes files; remove the copies you '
                        "don't want with a file manager, then rescan.",
                        style: text.bodyMedium,
                      ),
                      for (final copies in sets) ...[
                        const SizedBox(height: 20),
                        Text(
                          '${copies.first.title} · '
                          '${copies.first.displayArtist}',
                          style: text.titleSmall,
                        ),
                        for (final track in copies)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${qualityLabel(track)}\n${track.uri}',
                              style: text.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }
}
