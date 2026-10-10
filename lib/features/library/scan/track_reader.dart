import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/track.dart';
import 'codec_sniffer.dart';
import 'discovered_file.dart';
import 'mp4_inspector.dart';

/// Bump this whenever the reader learns to describe files better. The next
/// scan then re-reads every file an older version described.
const kTrackReaderVersion = 2;

/// Reads the tags and embedded artwork of [files] and returns one [Track] per
/// file. Does blocking file IO, so call it from a background isolate.
///
/// A file whose tags are corrupt or in an unknown format still becomes a
/// track, described by whatever the platform index or the file name offers.
List<Track> readTracks(List<DiscoveredFile> files, String artworkDir) {
  Directory(artworkDir).createSync(recursive: true);
  return [for (final file in files) readTrack(file, artworkDir)];
}

Track readTrack(DiscoveredFile file, String artworkDir) {
  AudioMetadata? tags;
  try {
    tags = readMetadata(File(file.path), getImage: true);
  } on Exception {
    tags = null;
  }

  final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
  final mp4 = _mp4Extensions.contains(extension)
      ? _inspectMp4(file.path)
      : null;

  final year = tags?.year?.year ?? file.year;
  final duration =
      _positiveDuration(tags?.duration) ??
      mp4?.duration ??
      file.duration ??
      Duration.zero;
  return Track(
    uri: file.path,
    fileName: p.basename(file.path),
    folder: p.dirname(file.path),
    title:
        _text(tags?.title) ??
        _text(file.title) ??
        p.basenameWithoutExtension(file.path),
    artist: _text(tags?.artist) ?? _text(file.artist),
    album: _text(tags?.album) ?? _text(file.album),
    albumArtist: _text(tags?.albumArtist),
    genre: _text(tags?.genres.firstOrNull),
    duration: duration,
    sizeBytes: file.sizeBytes,
    // For MP4 containers the codec comes from inside the file; for FLAC and
    // WAV the contents must confirm what the extension claims.
    codec: mp4?.audioCodec ?? sniffCodec(file.path, extension),
    sampleRate: _positive(tags?.sampleRate),
    bitDepth: extension == 'flac' ? _flacBitDepth(tags) : null,
    // The tag library's own bitrate field means something different for
    // every format, so the average is worked out from the file instead.
    bitrate: _averageBitrate(file.sizeBytes, duration),
    trackNumber: _positive(tags?.trackNumber) ?? file.trackNumber,
    discNumber: _positive(tags?.discNumber),
    // Some taggers write year 0 to mean "unknown".
    year: year != null && year > 0 ? year : null,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(
      file.addedMs ?? file.modifiedMs,
    ),
    dateModified: DateTime.fromMillisecondsSinceEpoch(file.modifiedMs),
    artPath: tags == null ? null : _cacheArtwork(tags.pictures, artworkDir),
  );
}

const _mp4Extensions = {'m4a', 'mp4', 'm4b'};

Mp4Info? _inspectMp4(String path) {
  try {
    final file = File(path).openSync();
    try {
      return inspectMp4(file);
    } finally {
      file.closeSync();
    }
  } on FileSystemException {
    return null;
  }
}

Duration? _positiveDuration(Duration? value) =>
    value != null && value > Duration.zero ? value : null;

String? _text(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? _positive(int? value) => value != null && value > 0 ? value : null;

/// For FLAC the tag library reports bits-per-sample × sample rate as its
/// "bitrate", which gives the bit depth back.
int? _flacBitDepth(AudioMetadata? tags) {
  final rate = tags?.sampleRate ?? 0;
  final product = tags?.bitrate ?? 0;
  if (rate <= 0 || product <= 0 || product % rate != 0) return null;
  final depth = product ~/ rate;
  return depth >= 8 && depth <= 32 ? depth : null;
}

/// Whole-file average in bits per second.
int? _averageBitrate(int sizeBytes, Duration duration) {
  if (sizeBytes <= 0 || duration.inMilliseconds <= 0) return null;
  return (sizeBytes * 8 * 1000 / duration.inMilliseconds).round();
}

/// Suffix of a cover waiting to be shrunk into the cache by the scanner.
const kPendingArtworkSuffix = '.src';

/// Covers above this size are parked for shrinking instead of cached as-is.
const _largeArtworkBytes = 150 * 1024;

/// Saves the front cover into the artwork cache and returns its path.
/// Files are named by content hash, so an album's tracks share one image.
String? _cacheArtwork(List<Picture> pictures, String artworkDir) {
  if (pictures.isEmpty) return null;
  final cover = pictures.firstWhere(
    (picture) => picture.pictureType == PictureType.coverFront,
    orElse: () => pictures.first,
  );
  if (cover.bytes.isEmpty) return null;
  // Always named .jpg; image decoders go by content, not extension.
  final cached = File(p.join(artworkDir, '${md5.convert(cover.bytes)}.jpg'));
  if (!cached.existsSync()) {
    final destination = cover.bytes.length > _largeArtworkBytes
        ? File('${cached.path}$kPendingArtworkSuffix')
        : cached;
    if (!destination.existsSync()) destination.writeAsBytesSync(cover.bytes);
  }
  return cached.path;
}
