import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/track.dart';

/// Tracks from the library picked for the listener's taste, worked out on
/// the device from what they play: the artists and genres played most, with
/// a lean towards tracks not played yet and favourites. Anything played in
/// the last two days is left out, no artist takes more than [perArtist]
/// places, and the order changes once a day. Empty until something has been
/// played.
List<Track> tasteMix(
  List<Track> library, {
  required DateTime now,
  int limit = 30,
  int perArtist = 3,
}) {
  final artistPlays = <String, int>{};
  final genrePlays = <String, int>{};
  for (final track in library) {
    if (track.playCount <= 0) continue;
    if (_artist(track) case final artist?) {
      artistPlays[artist] = (artistPlays[artist] ?? 0) + track.playCount;
    }
    if (_genre(track) case final genre?) {
      genrePlays[genre] = (genrePlays[genre] ?? 0) + track.playCount;
    }
  }
  if (artistPlays.isEmpty && genrePlays.isEmpty) return const [];
  final topArtist = artistPlays.values.fold(1, math.max);
  final topGenre = genrePlays.values.fold(1, math.max);

  final day = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(2020)).inDays;
  final playedLately = now.subtract(const Duration(days: 2));
  final scored = <(Track, double)>[];
  for (final track in library) {
    final lastPlayed = track.lastPlayedAt;
    if (lastPlayed != null && lastPlayed.isAfter(playedLately)) continue;
    final artist = (artistPlays[_artist(track)] ?? 0) / topArtist;
    final genre = (genrePlays[_genre(track)] ?? 0) / topGenre;
    if (artist == 0 && genre == 0) continue;
    scored.add((
      track,
      artist +
          0.5 * genre +
          (track.isFavorite ? 0.2 : 0) +
          (track.playCount == 0 ? 0.3 : 0) -
          0.03 * math.min(track.playCount, 10) +
          0.35 * _dailyJitter(track, day),
    ));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));

  final placed = <String, int>{};
  final mix = <Track>[];
  for (final (track, _) in scored) {
    final artist = _artist(track) ?? '';
    if ((placed[artist] ?? 0) >= perArtist) continue;
    placed[artist] = (placed[artist] ?? 0) + 1;
    mix.add(track);
    if (mix.length == limit) break;
  }
  return mix;
}

String? _artist(Track track) => _key(track.artist ?? track.albumArtist);
String? _genre(Track track) => _key(track.genre);

String? _key(String? value) {
  final key = value?.trim().toLowerCase();
  return key == null || key.isEmpty ? null : key;
}

/// A number from 0 to 1 that is the same for a track all day and changes
/// the next day.
double _dailyJitter(Track track, int day) {
  var hash = (track.uri.hashCode ^ (day * 0x9E3779B1)) & 0x7fffffff;
  hash = ((hash ^ (hash >> 15)) * 0x2c1b3c6d) & 0x7fffffff;
  hash = ((hash ^ (hash >> 12)) * 0x297a2d39) & 0x7fffffff;
  return (hash ^ (hash >> 15)) / 0x7fffffff;
}

/// The mix on the home screen. Worked out again when the library gains or
/// loses tracks, not after every play, so it doesn't shift while it plays.
final tasteMixProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(libraryStatsProvider.select((stats) => stats.value?.trackCount));
  final library = await ref.watch(libraryRepositoryProvider).tracks();
  return tasteMix(library, now: DateTime.now());
});
