import 'dart:convert';
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
const kTrackReaderVersion = 3;

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

  final sidecarMeta = _readSidecarMeta(file.path);
  final extension = p.extension(file.path).replaceFirst('.', '').toLowerCase();
  final mp4 = _mp4Extensions.contains(extension)
      ? _inspectMp4(file.path)
      : null;

  final year =
      tags?.year?.year ??
      _parseYear(sidecarMeta?['release_date']?.toString()) ??
      (sidecarMeta?['year'] as num?)?.toInt() ??
      file.year;
  final sidecarDurationMs = (sidecarMeta?['duration_ms'] as num?)?.toInt() ?? 0;
  final duration =
      _positiveDuration(tags?.duration) ??
      mp4?.duration ??
      (sidecarDurationMs > 0
          ? Duration(milliseconds: sidecarDurationMs)
          : null) ??
      file.duration ??
      Duration.zero;
  final embeddedArt = tags == null
      ? null
      : _cacheArtwork(tags.pictures, artworkDir);
  final artPath = embeddedArt ?? _cacheSidecarArtwork(file.path, artworkDir);

  return Track(
    uri: file.path,
    fileName: p.basename(file.path),
    folder: p.dirname(file.path),
    title:
        _text(tags?.title) ??
        _text(sidecarMeta?['title']?.toString()) ??
        _text(file.title) ??
        p.basenameWithoutExtension(file.path),
    artist:
        _text(tags?.artist) ??
        _text(sidecarMeta?['artist']?.toString()) ??
        _text(file.artist),
    album:
        _text(tags?.album) ??
        _text(sidecarMeta?['album']?.toString()) ??
        _text(file.album),
    albumArtist:
        _text(tags?.albumArtist) ??
        _text(sidecarMeta?['album_artist']?.toString()),
    genre:
        _text(tags?.genres.firstOrNull) ??
        _text(sidecarMeta?['genre']?.toString()),
    duration: duration,
    sizeBytes: file.sizeBytes,
    // For MP4 containers the codec comes from inside the file; for FLAC and
    // WAV the contents must confirm what the extension claims.
    codec: mp4?.audioCodec ?? sniffCodec(file.path, extension),
    sampleRate:
        _positive(tags?.sampleRate) ??
        _positive((sidecarMeta?['sample_rate'] as num?)?.toInt()),
    bitDepth:
        (extension == 'flac' ? _flacBitDepth(tags) : null) ??
        _positive((sidecarMeta?['bit_depth'] as num?)?.toInt()),
    // The tag library's own bitrate field means something different for
    // every format, so the average is worked out from the file instead.
    bitrate: _averageBitrate(file.sizeBytes, duration),
    trackNumber:
        _positive(tags?.trackNumber) ??
        _positive((sidecarMeta?['track_number'] as num?)?.toInt()) ??
        file.trackNumber,
    discNumber:
        _positive(tags?.discNumber) ??
        _positive((sidecarMeta?['disc_number'] as num?)?.toInt()),
    // Some taggers write year 0 to mean "unknown".
    year: year != null && year > 0 ? year : null,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(
      file.addedMs ?? file.modifiedMs,
    ),
    dateModified: DateTime.fromMillisecondsSinceEpoch(file.modifiedMs),
    artPath: artPath,
  );
}

Map<String, Object?>? _readSidecarMeta(String audioPath) {
  try {
    final file = File('${p.withoutExtension(audioPath)}.meta.json');
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
    }
  } on Object {
    // Ignore malformed or inaccessible sidecar metadata.
  }
  return null;
}

int? _parseYear(String? raw) {
  if (raw == null || raw.length < 4) return null;
  return int.tryParse(raw.substring(0, 4));
}

String? _cacheSidecarArtwork(String audioPath, String artworkDir) {
  try {
    final file = File('${p.withoutExtension(audioPath)}.cover.jpg');
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) return null;
    return _cacheArtworkBytes(bytes, artworkDir);
  } on Object {
    return null;
  }
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
  return _cacheArtworkBytes(cover.bytes, artworkDir);
}

String _cacheArtworkBytes(List<int> bytes, String artworkDir) {
  // Always named .jpg; image decoders go by content, not extension.
  final cached = File(p.join(artworkDir, '${md5.convert(bytes)}.jpg'));
  if (!cached.existsSync()) {
    final destination = bytes.length > _largeArtworkBytes
        ? File('${cached.path}$kPendingArtworkSuffix')
        : cached;
    if (!destination.existsSync()) destination.writeAsBytesSync(bytes);
  }
  return cached.path;
}
