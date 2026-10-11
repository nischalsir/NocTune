import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/widgets/noc_dialog.dart';
import '../../data/models/track.dart';

const _channel = MethodChannel('noctune/delete_audio');

/// Why a track's file could not be deleted, in words for the user.
class DeleteFailed implements Exception {
  const DeleteFailed(this.reason);

  final String reason;
}

/// Removes a track's file from the device for good. True when it is gone,
/// false when the user answered no to the phone's own question. Throws
/// [DeleteFailed] when it cannot be done.
final trackFileDeleterProvider = Provider<Future<bool> Function(Track track)>((
  ref,
) {
  final musicDir = ref.watch(appPathsProvider).musicDir;
  return (track) async {
    try {
      // What NocTune imported lives in its own folder and is its to delete.
      if (p.isWithin(musicDir, track.uri)) {
        await File(track.uri).delete();
        return true;
      }
      if (!Platform.isAndroid) {
        throw const DeleteFailed(
          'On this device NocTune can only delete files it imported.',
        );
      }
      // Anything else is shared storage, where Android asks the user itself.
      return await _channel.invokeMethod<bool>('delete', {'path': track.uri}) ??
          false;
    } on FileSystemException catch (error) {
      throw DeleteFailed(error.osError?.message ?? error.message);
    } on PlatformException catch (error) {
      throw DeleteFailed(error.message ?? 'The phone refused.');
    }
  };
});

/// Asks first, then removes [track]'s file from the device and the track
/// from the library and the queue.
Future<void> deleteTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  // Read now: the widget that opened this may be gone by the time it ends.
  final handler = ref.read(audioHandlerProvider);
  final repository = ref.read(libraryRepositoryProvider);
  final deleteFile = ref.read(trackFileDeleterProvider);
  final messenger = ScaffoldMessenger.of(context);

  void say(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  final confirmed = await showNocDialog<bool>(
    context,
    builder: (context) => NocDialogCard(
      title: 'Delete this song?',
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
      children: [
        Text(
          '"${track.title}" is removed from this device for good. This '
          'cannot be undone.',
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final bool deleted;
  try {
    deleted = await deleteFile(track);
  } on DeleteFailed catch (failure) {
    say("Couldn't delete ${track.title}. ${failure.reason}");
    return;
  }
  if (!deleted) return;

  await handler.removeTrack(track);
  await repository.removeTracks([track.uri]);
  say('Deleted ${track.title}');
}
