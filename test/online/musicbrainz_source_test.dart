import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/online/musicbrainz_source.dart';
import 'package:noctune/features/online/online_source.dart';

const _drake = '{"artists": [{"id": "d1", "name": "Drake", "score": 100}]}';

void main() {
  late List<Uri> asked;

  MusicBrainzSource source(Map<String, String> Function(Uri url) answers) =>
      MusicBrainzSource(
        gap: Duration.zero,
        fetch: (url) async {
          asked.add(url);
          return (status: 200, body: answers(url)['body']!);
        },
      );

  /// Answers the artist lookup with [artist], the last-few-years search
  /// with [recent] and the search of everything with [all].
  MusicBrainzSource answering({
    String artist = _drake,
    String recent = '{"release-groups": []}',
    String all = '{"release-groups": []}',
  }) => source(
    (url) => {
      'body': url.path.endsWith('/artist')
          ? artist
          : url.queryParameters['query']!.contains('firstreleasedate')
          ? recent
          : all,
    },
  );

  setUp(() => asked = []);

  test('finds the artist, then their newest releases first', () async {
    final found = await answering(
      recent:
          '{"release-groups": ['
          '{"id": "a", "title": "ICEMAN", "primary-type": "Album",'
          ' "first-release-date": "2026-05-15",'
          ' "artist-credit": [{"name": "Drake", "joinphrase": ""}]},'
          '{"id": "b", "title": "HABIBTI (FOMO)", "primary-type": "EP",'
          ' "first-release-date": "2026-10-02"},'
          '{"id": "c", "title": "DOG HOUSE", "primary-type": "Single",'
          ' "first-release-date": "2025-09"}]}',
    ).latest(' drake ');

    final (artist, releases) = found!;
    expect(artist, 'Drake');
    expect(releases.map((release) => release.title), [
      'HABIBTI (FOMO)',
      'ICEMAN',
      'DOG HOUSE',
    ]);
    expect(releases.first.artist, 'Drake');
    expect(
      releases.first.coverUrl,
      Uri.parse('https://coverartarchive.org/release-group/b/front-250'),
    );

    expect(asked.first.queryParameters, {
      'query': 'drake',
      'limit': '1',
      'fmt': 'json',
    });
    expect(asked[1].queryParameters['query'], startsWith('arid:d1 AND '));
    expect(asked, hasLength(2));
  });

  test('leaves out compilations, live sets and undated releases', () async {
    final (_, releases) = (await answering(
      recent:
          '{"release-groups": ['
          '{"id": "a", "title": "Care Package 2", "primary-type": "Album",'
          ' "secondary-types": ["Compilation"], "first-release-date": "2026"},'
          '{"id": "b", "title": "Live", "primary-type": "Album",'
          ' "secondary-types": ["Live"], "first-release-date": "2026"},'
          '{"id": "c", "title": "Undated", "primary-type": "Single"},'
          '{"id": "d", "title": "Video", "primary-type": "Other",'
          ' "first-release-date": "2026"},'
          '{"id": "e", "title": "FOMO", "primary-type": "Album",'
          ' "secondary-types": ["Soundtrack"], "first-release-date": "2026"}'
          ']}',
    ).latest('drake'))!;

    expect(releases.map((release) => release.title), ['FOMO']);
  });

  test('with nothing lately, falls back to everything they made', () async {
    final (_, releases) = (await answering(
      all:
          '{"release-groups": [{"id": "a", "title": "Pink Moon",'
          ' "primary-type": "Album", "first-release-date": "1972-02-25"}]}',
    ).latest('drake'))!;

    expect(releases.single.title, 'Pink Moon');
    expect(asked.last.queryParameters['query'], 'arid:d1');
  });

  test('words that do not clearly name an artist find nothing', () async {
    expect(
      await answering(
        artist: '{"artists": [{"id": "x", "name": "Nick Drake", "score": 85}]}',
      ).latest('drake song'),
      isNull,
    );
    expect(await answering(artist: '{"artists": []}').latest('zzz'), isNull);
    expect(asked, hasLength(2));
  });

  test('names NocTune on every request', () {
    expect(MusicBrainzSource.userAgent, startsWith('NocTune/'));
  });

  test('a busy or broken MusicBrainz is a search failure', () async {
    final busy = MusicBrainzSource(
      gap: Duration.zero,
      fetch: (_) async => (status: 503, body: ''),
    );
    expect(busy.latest('drake'), throwsA(isA<OnlineSearchException>()));
  });

  test('lists the songs of an official edition', () async {
    final songs =
        await source(
          (url) => {
            'body':
                '{"releases": ['
                '{"status": "Bootleg", "media": [{"tracks": [{"title": "X"}]}]},'
                '{"status": "Official", "media": ['
                '{"tracks": [{"title": "One", "length": 61000}]},'
                '{"tracks": [{"title": "Two", "artist-credit": ['
                '{"name": "Drake", "joinphrase": " & "},'
                '{"name": "Future", "joinphrase": ""}]}]}]}]}',
          },
        ).tracks(
          const Release(
            id: 'rg',
            title: 'Disc',
            artist: 'Drake',
            type: 'Album',
            date: '2026',
          ),
        );

    expect(asked.single.queryParameters['release-group'], 'rg');
    expect(songs.map((song) => song.title), ['One', 'Two']);
    expect(songs.first.artist, 'Drake');
    expect(songs.first.length, const Duration(seconds: 61));
    expect(songs.last.artist, 'Drake & Future');
  });
}
