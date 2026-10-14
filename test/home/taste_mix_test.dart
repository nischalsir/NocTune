import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/home/taste_mix.dart';

final _now = DateTime(2026, 10, 14, 20);
var _next = 0;

Track _track(
  String artist, {
  String? genre,
  int plays = 0,
  DateTime? lastPlayed,
  bool favourite = false,
}) {
  final id = ++_next;
  return Track(
    id: id,
    uri: '/music/$artist-$id.flac',
    fileName: '$artist-$id.flac',
    folder: '/music',
    title: '$artist $id',
    artist: artist,
    genre: genre,
    playCount: plays,
    lastPlayedAt: lastPlayed,
    isFavorite: favourite,
    dateAdded: DateTime(2026),
    dateModified: DateTime(2026),
  );
}

void main() {
  test('nothing played yet gives no mix', () {
    expect(tasteMix([_track('Aurora'), _track('Swar')], now: _now), isEmpty);
  });

  test('leans to the artists played most', () {
    final library = [
      _track('Aurora', plays: 20, lastPlayed: DateTime(2026, 9)),
      _track('Swar', plays: 1, lastPlayed: DateTime(2026, 9)),
      _track('Aurora'),
      _track('Swar'),
      _track('Stranger'),
    ];

    final mix = tasteMix(library, now: _now);

    expect(mix.first.artist, 'Aurora');
    // An artist never played, with no shared genre, is not suggested.
    expect(mix.map((track) => track.artist), isNot(contains('Stranger')));
  });

  test('a genre played brings in other artists of it', () {
    final library = [
      _track('Aurora', genre: 'Indie', plays: 5, lastPlayed: DateTime(2026, 9)),
      _track('Lena', genre: 'indie'),
      _track('Metal Band', genre: 'Metal'),
    ];

    final artists = tasteMix(library, now: _now).map((track) => track.artist);

    expect(artists, contains('Lena'));
    expect(artists, isNot(contains('Metal Band')));
  });

  test('leaves out what was played in the last two days', () {
    final recent = _track('Aurora', plays: 9, lastPlayed: _now);
    final library = [recent, _track('Aurora')];

    expect(tasteMix(library, now: _now), isNot(contains(recent)));
  });

  test('no artist takes more than three places', () {
    final library = [
      _track('Aurora', plays: 50, lastPlayed: DateTime(2026, 9)),
      for (var i = 0; i < 10; i++) _track('Aurora'),
      _track('Swar', plays: 1, lastPlayed: DateTime(2026, 9)),
      _track('Swar'),
    ];

    final mix = tasteMix(library, now: _now);

    expect(mix.where((track) => track.artist == 'Aurora'), hasLength(3));
    expect(mix.map((track) => track.artist), contains('Swar'));
  });

  test('the same all day, and different another day', () {
    final library = [
      _track('Aurora', plays: 3, lastPlayed: DateTime(2026, 9)),
      _track('Swar', plays: 3, lastPlayed: DateTime(2026, 9)),
      _track('Lena', plays: 3, lastPlayed: DateTime(2026, 9)),
      for (final artist in ['Aurora', 'Swar', 'Lena'])
        for (var i = 0; i < 3; i++) _track(artist),
    ];

    final morning = tasteMix(library, now: DateTime(2026, 10, 14, 8));
    final evening = tasteMix(library, now: DateTime(2026, 10, 14, 22));
    expect(evening, morning);

    final days = {
      for (var day = 1; day <= 10; day++)
        tasteMix(library, now: DateTime(2026, 11, day)).first.uri,
    };
    expect(days.length, greaterThan(1));
  });
}
