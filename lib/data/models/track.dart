import 'package:flutter/foundation.dart';

/// One audio file in the local library.
@immutable
class Track {
  const Track({
    this.id = 0,
    required this.uri,
    required this.fileName,
    required this.folder,
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.duration = Duration.zero,
    this.sizeBytes = 0,
    this.codec,
    this.sampleRate,
    this.bitDepth,
    this.bitrate,
    this.trackNumber,
    this.discNumber,
    this.year,
    required this.dateAdded,
    required this.dateModified,
    this.artPath,
    this.isFavorite = false,
    this.playCount = 0,
    this.lastPlayedAt,
  });

  factory Track.fromRow(Map<String, Object?> row) => Track(
    id: row['id']! as int,
    uri: row['uri']! as String,
    fileName: row['file_name']! as String,
    folder: row['folder']! as String,
    title: row['title']! as String,
    artist: row['artist'] as String?,
    album: row['album'] as String?,
    albumArtist: row['album_artist'] as String?,
    genre: row['genre'] as String?,
    duration: Duration(milliseconds: row['duration_ms']! as int),
    sizeBytes: row['size_bytes']! as int,
    codec: row['codec'] as String?,
    sampleRate: row['sample_rate'] as int?,
    bitDepth: row['bit_depth'] as int?,
    bitrate: row['bitrate'] as int?,
    trackNumber: row['track_no'] as int?,
    discNumber: row['disc_no'] as int?,
    year: row['year'] as int?,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(row['date_added']! as int),
    dateModified: DateTime.fromMillisecondsSinceEpoch(
      row['date_modified']! as int,
    ),
    artPath: row['art_path'] as String?,
    isFavorite: row['is_favorite'] == 1,
    playCount: row['play_count']! as int,
    lastPlayedAt: switch (row['last_played_at']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
  );

  /// Database id; 0 until the track has been stored.
  final int id;

  /// Where the audio lives: an absolute file path, or a `content://` URI.
  final String uri;
  final String fileName;

  /// Directory containing the file, used for folder browsing.
  final String folder;
  final String title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final Duration duration;
  final int sizeBytes;

  /// Lower-case codec name, e.g. `flac`, `aac` or `eac3-joc`.
  final String? codec;

  /// Sample rate in Hz.
  final int? sampleRate;

  /// Bits per sample, where the format records it (FLAC).
  final int? bitDepth;

  /// Average bitrate of the whole file, in bits per second.
  final int? bitrate;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final DateTime dateAdded;

  /// File modification time, used to skip unchanged files on rescan.
  final DateTime dateModified;

  /// Cached artwork image on disk, if the file had embedded artwork.
  final String? artPath;
  final bool isFavorite;
  final int playCount;
  final DateTime? lastPlayedAt;

  String get displayArtist => artist ?? 'Unknown artist';
  String get displayAlbum => album ?? 'Unknown album';

  /// The URI handed to the audio engine.
  Uri get playbackUri =>
      uri.startsWith('content://') ? Uri.parse(uri) : Uri.file(uri);

  /// Columns describing the file itself. Favourites, play counts and the
  /// date added are owned by the user and never overwritten by a rescan.
  Map<String, Object?> toMetadataRow() => {
    'uri': uri,
    'file_name': fileName,
    'folder': folder,
    'title': title,
    'artist': artist,
    'album': album,
    'album_artist': albumArtist,
    'genre': genre,
    'duration_ms': duration.inMilliseconds,
    'size_bytes': sizeBytes,
    'codec': codec,
    'sample_rate': sampleRate,
    'bit_depth': bitDepth,
    'bitrate': bitrate,
    'track_no': trackNumber,
    'disc_no': discNumber,
    'year': year,
    'date_modified': dateModified.millisecondsSinceEpoch,
    'art_path': artPath,
  };

  @override
  bool operator ==(Object other) => other is Track && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
