import 'package:flutter/foundation.dart';

/// File extensions NocTune treats as music.
const kAudioExtensions = {
  'flac',
  'm4a',
  'mp4',
  'mp3',
  'aac',
  'wav',
  'ogg',
  'opus',
};

/// An audio file found on the device, before its tags have been read.
@immutable
class DiscoveredFile {
  const DiscoveredFile({
    required this.path,
    required this.sizeBytes,
    required this.modifiedMs,
    this.addedMs,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
  });

  final String path;
  final int sizeBytes;
  final int modifiedMs;

  /// When the platform first saw the file, if it tracks that.
  final int? addedMs;

  // What the platform's own media index knows. Used as a fallback when the
  // file's tags can't be read.
  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final int? trackNumber;
  final int? year;
}

/// Somewhere audio files can be found.
abstract interface class LibrarySource {
  Future<List<DiscoveredFile>> discover();
}
