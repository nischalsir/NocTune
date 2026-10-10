import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../data/models/track.dart';

/// Asks for a playlist name. Returns null if the user cancels or leaves it
/// blank. [initialName] is set when renaming.
Future<String?> askPlaylistName(BuildContext context, {String? initialName}) {
  final controller = TextEditingController(text: initialName);
  void submit(BuildContext context) {
    final name = controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initialName == null ? 'New playlist' : 'Rename playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => submit(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => submit(context),
          child: Text(initialName == null ? 'Create' : 'Rename'),
        ),
      ],
    ),
  );
}

/// Lets the user add [track] to an existing playlist or a new one.
Future<void> showAddToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  final repository = ref.read(libraryRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);

  Future<void> add(int playlistId, String name) async {
    await repository.addToPlaylist(playlistId, track.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Added to $name')));
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: context.noc.glassSolid,
    builder: (sheetContext) => SafeArea(
      child: Consumer(
        builder: (_, ref, _) {
          final playlists = ref.watch(playlistsProvider).value ?? const [];
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('New playlist'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final name = await askPlaylistName(context);
                  if (name == null) return;
                  await add(await repository.createPlaylist(name), name);
                },
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.trackCount} tracks'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    add(playlist.id, playlist.name);
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}
