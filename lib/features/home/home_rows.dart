import 'package:flutter/material.dart';

import '../../data/models/playlist.dart';
import '../../data/models/track.dart';

/// What the home list shows. The order here is the order of the menu.
enum HomeSort {
  recent('Recent', Icons.schedule),
  mostPlayed('Most Played', Icons.bar_chart),
  last7Days('Last 7 Days', Icons.date_range),
  last30Days('Last 30 Days', Icons.calendar_month),
  topArtists('Top Artists', Icons.people),
  topAlbums('Top Albums', Icons.album);

  const HomeSort(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One line of the home list.
sealed class HomeRow {
  const HomeRow();

  /// Identifies the row across rebuilds of the list.
  String get key;
}

/// A day separating the plays of the "Recent" list.
final class DateHeaderRow extends HomeRow {
  const DateHeaderRow(this.label);

  final String label;

  @override
  String get key => 'date_$label';
}

final class TrackRow extends HomeRow {
  const TrackRow(
    this.track, {
    this.badge,
    this.isNowPlaying = false,
    this.playedAt,
  });

  final Track track;

  /// A count shown at the end of the row: plays in the period, or "3×" for
  /// a track played several times in one day.
  final String? badge;

  /// Whether this is the track loaded in the player.
  final bool isNowPlaying;
  final DateTime? playedAt;

  @override
  String get key => isNowPlaying
      ? 'nowplaying_${track.id}'
      : 'track_${track.id}_${playedAt?.millisecondsSinceEpoch ?? 0}';
}

final class AlbumRow extends HomeRow {
  const AlbumRow(this.album);

  final TrackGroupSummary album;

  @override
  String get key => 'album_${album.name}';
}

final class ArtistRow extends HomeRow {
  const ArtistRow(this.artist);

  final TrackGroupSummary artist;

  @override
  String get key => 'artist_${artist.name}';
}

/// The "Recent" list: the track in the player first, then the play log
/// grouped by day. A track played more than once in a day appears once,
/// with the number of plays as its badge.
List<HomeRow> recentRows(
  List<PlayedTrack> log, {
  required DateTime now,
  Track? nowPlaying,
}) {
  final rows = <HomeRow>[];
  var entries = log;
  if (nowPlaying != null) {
    rows.add(TrackRow(nowPlaying, isNowPlaying: true));
    // The newest entry is the play that is on right now; it is the row above.
    if (entries.isNotEmpty && entries.first.track.id == nowPlaying.id) {
      entries = entries.sublist(1);
    }
  }

  final days = <DateTime, List<PlayedTrack>>{};
  for (final entry in entries) {
    final at = entry.playedAt;
    days.putIfAbsent(DateTime(at.year, at.month, at.day), () => []).add(entry);
  }
  for (final MapEntry(key: day, value: plays) in days.entries) {
    final label = dayLabel(day, now);
    if (label != null) rows.add(DateHeaderRow(label));
    final counts = <int, int>{};
    for (final play in plays) {
      counts.update(play.track.id, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final play in plays) {
      final count = counts.remove(play.track.id);
      if (count == null) continue;
      rows.add(
        TrackRow(
          play.track,
          badge: count > 1 ? '$count×' : null,
          playedAt: play.playedAt,
        ),
      );
    }
  }
  return rows;
}

/// A ranked list: the track in the player first, then [ranked] in the order
/// given, each with its play count.
List<HomeRow> rankedRows(List<TrackPlays> ranked, {Track? nowPlaying}) => [
  if (nowPlaying != null) TrackRow(nowPlaying, isNowPlaying: true),
  for (final entry in ranked)
    if (entry.track.id != nowPlaying?.id)
      TrackRow(entry.track, badge: playCountBadge(entry.plays)),
];

/// "Yesterday", a date such as "4 Oct 2026", or nothing for today.
String? dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(day.year, day.month, day.day);
  if (date == today) return null;
  if (date == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String? playCountBadge(int count) {
  if (count <= 0) return null;
  return count >= 1000 ? '${(count / 1000).toStringAsFixed(1)}k' : '$count';
}

/// Listening time in words: "12d 4h 9m", "3h 20m 5s" or "4m 12s".
String formatListeningTime(int totalSeconds) {
  if (totalSeconds <= 0) return '--';
  final days = totalSeconds ~/ 86400;
  final hours = totalSeconds % 86400 ~/ 3600;
  final minutes = totalSeconds % 3600 ~/ 60;
  final seconds = totalSeconds % 60;
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m ${seconds}s';
  return '${minutes}m ${seconds}s';
}
