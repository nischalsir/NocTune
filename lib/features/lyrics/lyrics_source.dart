import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import 'lyrics.dart';

/// Where a track's lyrics came from.
enum LyricsOrigin {
  imported('Imported file'),
  sidecar('.lrc file beside the track'),
  embedded('Embedded in the audio file');

  const LyricsOrigin(this.label);

  final String label;
}

@immutable
class LoadedLyrics {
  const LoadedLyrics(this.lyrics, this.origin);

  final Lyrics lyrics;
  final LyricsOrigin origin;
}

/// Finds lyrics for [track], all from this device: a file the user imported
/// for it, then an `.lrc` file with the same name next to it, then lyrics
/// embedded in the audio file's tags. Returns null when there are none.
Future<LoadedLyrics?> loadLyrics(
  Track track,
  LibraryRepository repository,
) async {
  final imported = await repository.importedLyrics(track.id);
  if (imported != null) {
    final lyrics = parseLyrics(imported);
    if (lyrics != null) return LoadedLyrics(lyrics, LyricsOrigin.imported);
  }
  if (track.uri.startsWith('content://')) return null;

  final path = track.uri;
  final found = await Isolate.run(() => readLyricsFromFiles(path));
  for (final (text, origin) in [
    (found.sidecar, LyricsOrigin.sidecar),
    (found.embedded, LyricsOrigin.embedded),
  ]) {
    final lyrics = text == null ? null : parseLyrics(text);
    if (lyrics != null) return LoadedLyrics(lyrics, origin);
  }
  return null;
}

/// Reads the raw lyric text stored with an audio file. Does blocking file
/// IO, so it runs in a background isolate.
({String? sidecar, String? embedded}) readLyricsFromFiles(String audioPath) {
  String? sidecar;
  try {
    final file = File('${p.withoutExtension(audioPath)}.lrc');
    if (file.existsSync()) sidecar = decodeLyricsBytes(file.readAsBytesSync());
  } on FileSystemException {
    // Android only lets an app read media files it didn't create, so a
    // neighbouring .lrc may be out of reach. Embedded lyrics still work.
  }

  String? embedded;
  try {
    embedded = readMetadata(File(audioPath)).lyrics;
  } on Exception {
    // Unreadable tags simply mean no embedded lyrics.
  }
  return (sidecar: sidecar, embedded: embedded);
}

/// Decodes lyric file bytes as UTF-8, falling back to Latin-1 for the older
/// files that predate it.
String decodeLyricsBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

typedef LyricsKey = ({int trackId, String uri});

/// Lyrics for a track, loaded once and kept while the track is in use.
final lyricsProvider = FutureProvider.family<LoadedLyrics?, LyricsKey>((
  ref,
  key,
) async {
  final repository = ref.watch(libraryRepositoryProvider);
  final track = await repository.trackById(key.trackId);
  return track == null ? null : loadLyrics(track, repository);
});

/// Thrown when a picked file holds nothing usable as lyrics.
class InvalidLyricsFile implements Exception {
  const InvalidLyricsFile();
}

/// Lets the user pick an `.lrc` or text file and attaches it to [track].
/// Returns false if they cancelled. Throws [InvalidLyricsFile] when the file
/// has no lyric lines; nothing is saved in that case.
Future<bool> importLyricsFor(Track track, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['lrc', 'txt'],
  );
  final path = picked?.path;
  if (path == null) return false;

  final String text;
  try {
    text = decodeLyricsBytes(await File(path).readAsBytes());
  } on FileSystemException {
    throw const InvalidLyricsFile();
  }
  if (parseLyrics(text) == null) throw const InvalidLyricsFile();

  await ref.read(libraryRepositoryProvider).setImportedLyrics(track.id, text);
  ref.invalidate(lyricsProvider((trackId: track.id, uri: track.uri)));
  return true;
}
