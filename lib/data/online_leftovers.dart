import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'repositories/library_repository.dart';

/// The folders, inside the app's music folder, that the online search used
/// to download into (Jamendo, Audius and the Internet Archive).
const kOnlineDownloadFolders = ['Jamendo', 'Audius', 'Internet Archive'];

/// Covers the online search cached, named after their source.
final _onlineCover = RegExp(r'^(jamendo|audius|archive)-');

/// Settings and caches only the online search used.
const _onlinePreferences = [
  'online_search_cache',
  'online_search_cache_v2',
  'online_album_cache',
  'online_search_enabled',
  'online_source_jamendo',
  'online_source_audius',
  'online_source_archive',
];

const _doneKey = 'online_leftovers_removed';

/// Removes, once, what the online search left behind: the songs it
/// downloaded (from the device and from the library), their cached covers
/// and its saved settings. Later launches do nothing.
Future<void> removeOnlineLeftovers({
  required SharedPreferences preferences,
  required LibraryRepository repository,
  required String musicDir,
  required String artworkDir,
}) async {
  if (preferences.getBool(_doneKey) ?? false) return;

  final folders = [
    for (final name in kOnlineDownloadFolders) p.join(musicDir, name),
  ];
  final known = (await repository.fingerprints()).keys;
  final downloaded = [
    for (final uri in known)
      if (folders.any((folder) => p.isWithin(folder, uri))) uri,
  ];
  if (downloaded.isNotEmpty) await repository.removeTracks(downloaded);

  for (final folder in folders) {
    await _deleteQuietly(Directory(folder));
  }
  final covers = Directory(artworkDir);
  if (await covers.exists()) {
    await for (final entry in covers.list()) {
      if (entry is File && _onlineCover.hasMatch(p.basename(entry.path))) {
        await _deleteQuietly(entry);
      }
    }
  }
  for (final key in _onlinePreferences) {
    await preferences.remove(key);
  }
  await preferences.setBool(_doneKey, true);
}

/// Deletes [entity] if it is there; a file that can't be deleted is left for
/// the user rather than stopping the app from starting.
Future<void> _deleteQuietly(FileSystemEntity entity) async {
  try {
    if (await entity.exists()) await entity.delete(recursive: true);
  } on FileSystemException {
    // Left as it is.
  }
}
