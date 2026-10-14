import 'package:flutter/foundation.dart';

import 'track.dart';

/// A user-created playlist.
@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackCount,
    this.coverPath,
    this.artPath,
  });

  factory Playlist.fromRow(Map<String, Object?> row) => Playlist(
    id: row['id']! as int,
    name: row['name']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    trackCount: row['track_count']! as int,
    coverPath: row['cover_path'] as String?,
    artPath: row['art_path'] as String?,
  );

  final int id;
  final String name;
  final DateTime createdAt;
  final int trackCount;

  /// A picture the user chose for this playlist, if they have.
  final String? coverPath;

  /// Artwork of the first track in it that has any.
  final String? artPath;

  /// What to picture the playlist with: the user's choice, else its tracks'.
  String? get cover => coverPath ?? artPath;
}

/// One album, artist, genre or folder, with enough detail to list it.
@immutable
class TrackGroupSummary {
  const TrackGroupSummary({
    required this.name,
    required this.trackCount,
    this.artPath,
    this.artist,
    this.playCount = 0,
  });

  factory TrackGroupSummary.fromRow(Map<String, Object?> row) =>
      TrackGroupSummary(
        name: row['name']! as String,
        trackCount: row['track_count']! as int,
        artPath: row['art_path'] as String?,
        artist: row['artist'] as String?,
        playCount: row['plays'] as int? ?? 0,
      );

  final String name;
  final int trackCount;

  /// Artwork from one of the group's tracks.
  final String? artPath;

  /// An artist credited in the group; meaningful for albums.
  final String? artist;

  /// Plays of the group's tracks added together; only filled in by the
  /// most-played queries.
  final int playCount;
}

/// Headline numbers for the whole library.
@immutable
class LibraryStats {
  const LibraryStats({
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.totalDuration,
    this.playCount = 0,
    this.listenedDuration = Duration.zero,
  });

  final int trackCount;
  final int albumCount;
  final int artistCount;
  final Duration totalDuration;

  /// How many times tracks have been played in this app, in total.
  final int playCount;

  /// Time spent listening in this app. Before version 5 of the database
  /// only an estimate was kept, every play at the track's full length; that
  /// estimate is included as it was.
  final Duration listenedDuration;
}

/// One entry of the play log: a track and when it was played.
typedef PlayedTrack = ({Track track, DateTime playedAt});

/// A track and how many times it was played in some period.
typedef TrackPlays = ({Track track, int plays});
