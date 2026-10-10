import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/home/home_rows.dart';

Track _track(int id, String title) => Track(
  id: id,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

/// A compact picture of the rows: "#Yesterday" for a day header, and
/// "Title", "Title[3×]" or ">Title" (now playing) for tracks.
List<String> _describe(List<HomeRow> rows) => [
  for (final row in rows)
    switch (row) {
      DateHeaderRow(:final label) => '#$label',
      TrackRow(:final track, :final badge, :final isNowPlaying) =>
        '${isNowPlaying ? '>' : ''}${track.title}'
            '${badge == null ? '' : '[$badge]'}',
      AlbumRow(:final album) => 'album:${album.name}',
      ArtistRow(:final artist) => 'artist:${artist.name}',
    },
];

void main() {
  final now = DateTime(2026, 10, 10, 15);
  final a = _track(1, 'A');
  final b = _track(2, 'B');
  final c = _track(3, 'C');

  group('recent', () {
    test('today has no header; earlier days are labelled', () {
      final rows = recentRows([
        (track: a, playedAt: DateTime(2026, 10, 10, 14)),
        (track: b, playedAt: DateTime(2026, 10, 9, 23)),
        (track: c, playedAt: DateTime(2026, 10, 4, 8)),
      ], now: now);

      expect(_describe(rows), ['A', '#Yesterday', 'B', '#4 Oct 2026', 'C']);
    });

    test('repeats within a day become one row with a count', () {
      final rows = recentRows([
        (track: a, playedAt: DateTime(2026, 10, 9, 20)),
        (track: b, playedAt: DateTime(2026, 10, 9, 19)),
        (track: a, playedAt: DateTime(2026, 10, 9, 18)),
        (track: a, playedAt: DateTime(2026, 10, 9, 17)),
        (track: a, playedAt: DateTime(2026, 10, 8, 9)),
      ], now: now);

      expect(_describe(rows), ['#Yesterday', 'A[3×]', 'B', '#8 Oct 2026', 'A']);
    });

    test('the track in the player leads and its current play is not listed '
        'twice', () {
      final rows = recentRows(
        [
          (track: a, playedAt: DateTime(2026, 10, 10, 14, 59)),
          (track: b, playedAt: DateTime(2026, 10, 10, 14)),
          (track: a, playedAt: DateTime(2026, 10, 10, 13)),
        ],
        now: now,
        nowPlaying: a,
      );

      // A's earlier play today is still part of the history.
      expect(_describe(rows), ['>A', 'B', 'A']);
    });

    test('a loaded track that was not the last thing played keeps the whole '
        'log', () {
      final rows = recentRows(
        [(track: b, playedAt: DateTime(2026, 10, 10, 14))],
        now: now,
        nowPlaying: a,
      );

      expect(_describe(rows), ['>A', 'B']);
    });

    test('an empty log gives an empty list', () {
      expect(recentRows(const [], now: now), isEmpty);
    });

    test('rows of the same track on different days have different keys', () {
      final rows = recentRows([
        (track: a, playedAt: DateTime(2026, 10, 9, 20)),
        (track: a, playedAt: DateTime(2026, 10, 8, 20)),
      ], now: now);

      final keys = rows.map((row) => row.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('ranked', () {
    test('keeps the given order and shows each count', () {
      final rows = rankedRows([
        (track: a, plays: 12),
        (track: b, plays: 1500),
        (track: c, plays: 0),
      ]);

      expect(_describe(rows), ['A[12]', 'B[1.5k]', 'C']);
    });

    test('the track in the player comes first, without being repeated', () {
      final rows = rankedRows([
        (track: a, plays: 9),
        (track: b, plays: 4),
      ], nowPlaying: b);

      expect(_describe(rows), ['>B', 'A[9]']);
    });
  });

  test('day labels handle month and year boundaries', () {
    final newYear = DateTime(2027, 1, 1, 0, 30);
    expect(dayLabel(DateTime(2027, 1, 1), newYear), isNull);
    expect(dayLabel(DateTime(2026, 12, 31, 23, 59), newYear), 'Yesterday');
    expect(dayLabel(DateTime(2026, 12, 30), newYear), '30 Dec 2026');
  });

  test('listening time is written in words', () {
    expect(formatListeningTime(0), '--');
    expect(formatListeningTime(59), '0m 59s');
    expect(formatListeningTime(4 * 60 + 12), '4m 12s');
    expect(formatListeningTime(3 * 3600 + 20 * 60 + 5), '3h 20m 5s');
    expect(formatListeningTime(2 * 86400 + 4 * 3600 + 9 * 60 + 30), '2d 4h 9m');
  });
}
