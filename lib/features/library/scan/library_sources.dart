import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'discovered_file.dart';

const _mediaStore = MethodChannel('noctune/media_store');
const _artwork = MethodChannel('noctune/artwork');

/// The Android version, which decides which storage permission applies.
Future<int> androidSdkInt() async =>
    await _mediaStore.invokeMethod<int>('sdkInt') ?? 0;

/// Music Android has already indexed across the device's shared storage.
class MediaStoreSource implements LibrarySource {
  const MediaStoreSource();

  @override
  Future<List<DiscoveredFile>> discover() async {
    final rows =
        await _mediaStore.invokeListMethod<Map<Object?, Object?>>(
          'queryAudio',
        ) ??
        const [];
    return [
      for (final row in rows)
        DiscoveredFile(
          path: row['path']! as String,
          sizeBytes: row['sizeBytes']! as int,
          modifiedMs: row['modifiedMs']! as int,
          addedMs: row['addedMs'] as int?,
          title: row['title'] as String?,
          artist: row['artist'] as String?,
          album: row['album'] as String?,
          duration: Duration(milliseconds: row['durationMs']! as int),
          trackNumber: row['trackNumber'] as int?,
          year: row['year'] as int?,
        ),
    ];
  }
}

/// Audio files inside one folder and its subfolders: imported files, and on
/// iOS anything the user has put in the app's Files folder.
class DirectorySource implements LibrarySource {
  const DirectorySource(this.directory);

  final Directory directory;

  @override
  Future<List<DiscoveredFile>> discover() async {
    if (!directory.existsSync()) return const [];
    final files = <DiscoveredFile>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path).replaceFirst('.', '');
      if (!kAudioExtensions.contains(extension.toLowerCase())) continue;
      final stat = entity.statSync();
      files.add(
        DiscoveredFile(
          path: entity.path,
          sizeBytes: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }
    return files;
  }
}

/// Longest edge, in pixels, of a cover kept in the artwork cache.
const _artworkMaxSize = 1000;

/// Asks the platform to shrink a cover image. Returns false where the
/// platform has no shrinker, so the caller keeps the original.
Future<bool> shrinkArtworkOnPlatform(String source, String target) async {
  try {
    return await _artwork.invokeMethod<bool>('downscale', {
          'source': source,
          'target': target,
          'maxSize': _artworkMaxSize,
        }) ??
        false;
  } on MissingPluginException {
    return false;
  }
}
