import 'package:flutter/foundation.dart';

/// A user-created playlist.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackCount,
  });

  factory Playlist.fromRow(Map<String, Object?> row) => Playlist(
    id: row['id']! as int,
    name: row['name']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    trackCount: row['track_count']! as int,
  );

  final int id;
  final String name;
  final DateTime createdAt;
  final int trackCount;
}

/// One album, artist, genre or folder, with enough detail to list it.
@immutable
class TrackGroupSummary {
  const TrackGroupSummary({
    required this.name,
    required this.trackCount,
    this.artPath,
    this.artist,
  });

  factory TrackGroupSummary.fromRow(Map<String, Object?> row) =>
      TrackGroupSummary(
        name: row['name']! as String,
        trackCount: row['track_count']! as int,
        artPath: row['art_path'] as String?,
        artist: row['artist'] as String?,
      );

  final String name;
  final int trackCount;

  /// Artwork from one of the group's tracks.
  final String? artPath;

  /// An artist credited in the group; meaningful for albums.
  final String? artist;
}

/// Headline numbers for the whole library.
@immutable
class LibraryStats {
  const LibraryStats({
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.totalDuration,
  });

  final int trackCount;
  final int albumCount;
  final int artistCount;
  final Duration totalDuration;
}
