import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/online/archive_source.dart';
import 'package:noctune/features/online/online_source.dart';

/// Real answers, trimmed: a search finding a Live Music Archive show, a
/// public-domain recording and one with two creators; and that show's files,
/// out of order, with a FLAC, a thumbnail and one private MP3 among them.
final _search = File('test/online/fixtures/archive_search.json')
    .readAsStringSync();
final _item = File('test/online/fixtures/archive_item.json').readAsStringSync();

const _show = OnlineAlbum(
  source: OnlineSourceId.archive,
  id: 'samh2024-05-01.179350.ps1.s2.e.sbd.wilson.jenkins.richteratmosphere.flac2448',
  title: 'Stu Allen and Mars Hotel Live at Ashkenaz on 2024-05-01',
  creator: 'Stu Allen and Mars Hotel',
  kind: OnlineAlbumKind.show,
);

/// An item whose files are [files].
String _itemWith(List<Map<String, Object?>> files) => jsonEncode({
  'metadata': {'identifier': 'gd77 x'},
  'files': files,
});

Matcher _fails(OnlineFailure failure) => throwsA(
  isA<OnlineSearchException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  late List<Uri> asked;

  ArchiveSource source(FutureOr<OnlineResponse> Function(Uri url) answer) =>
      ArchiveSource(
        fetch: (url) async {
          asked.add(url);
          return answer(url);
        },
      );

  ArchiveSource answering(String body) =>
      source((_) => (status: 200, body: body));

  setUp(() => asked = []);

  test('asks only for shareable recordings', () async {
    await answering(_search).search(' grateful dead ');

    final url = asked.single;
    expect(url.host, 'archive.org');
    expect(url.path, '/advancedsearch.php');
    expect(
      url.queryParameters['q'],
      '(grateful dead) AND ((mediatype:audio AND '
      '(licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)) OR '
      'collection:etree) AND (format:"VBR MP3" OR format:"128Kbps MP3" OR '
      'format:"64Kbps MP3") AND NOT collection:stream_only',
    );
    expect(url.queryParametersAll['fl[]'], [
      'identifier',
      'title',
      'creator',
      'mediatype',
      'licenseurl',
    ]);
    expect(url.queryParameters['rows'], '20');
    expect(url.queryParameters['output'], 'json');
  });

  test('characters with a meaning in the query are escaped', () async {
    await answering(_search).search(r'ac/dc (live) "best" -1 a:b');

    expect(
      asked.single.queryParameters['q'],
      startsWith(r'(ac\/dc \(live\) \"best\" \-1 a\:b) AND '),
    );
  });

  test('results are albums and shows with covers', () async {
    final albums = (await answering(_search).search('x')).cast<OnlineAlbum>();

    expect(albums.map((album) => album.kind), [
      OnlineAlbumKind.show,
      OnlineAlbumKind.album,
      OnlineAlbumKind.album,
    ]);
    expect(albums.first, _show);
    expect(albums.first.title, _show.title);
    expect(albums.first.creator, 'Stu Allen and Mars Hotel');
    expect(
      albums.first.imageUrl.toString(),
      'https://archive.org/services/img/${_show.id}',
    );
    expect(
      albums[1].licenceUrl,
      'http://creativecommons.org/publicdomain/mark/1.0/',
    );
    expect(albums[2].creator, 'Common Rotation');
  });

  test(
    'an item lists its MP3s in track order, skipping private files',
    () async {
      final tracks = await answering(_item).tracks(_show);

      expect(
        asked.single.toString(),
        'https://archive.org/metadata/${_show.id}',
      );
      expect(tracks.map((track) => track.title), [
        '//Iko Iko >',
        'Might as Well',
      ]);
      final first = tracks.first;
      expect(first.source, OnlineSourceId.archive);
      expect(first.id, '${_show.id}/01.Iko Iko.mp3');
      expect(first.album, _show.title);
      expect(first.artist, _show.creator);
      expect(first.duration, const Duration(minutes: 5, seconds: 6));
      expect(
        first.imageUrl.toString(),
        'https://archive.org/services/img/${_show.id}',
      );
      expect(first.downloadUrl, first.streamUrl);
    },
  );

  test('lengths in seconds or h:mm:ss; title falls back to the name', () async {
    final tracks = await answering(
      _itemWith([
        {'name': 'a.mp3', 'format': 'VBR MP3', 'length': '5232.01'},
        {'name': 'b.mp3', 'format': 'VBR MP3', 'length': '1:02:03'},
      ]),
    ).tracks(_show);

    expect(tracks.map((track) => track.title), ['a', 'b']);
    expect(tracks.map((track) => track.duration), [
      const Duration(seconds: 5232),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    ]);
  });

  test('128Kbps, then 64Kbps MP3 when there is no VBR MP3', () async {
    final tracks = await answering(
      _itemWith([
        {'name': 'low.mp3', 'format': '64Kbps MP3'},
        {'name': 'high.mp3', 'format': '128Kbps MP3'},
        {'name': 'all.zip', 'format': '64Kbps MP3 ZIP'},
      ]),
    ).tracks(_show);

    expect(tracks.map((track) => track.title), ['high']);
  });

  test('tracks without a number come last, then by name', () async {
    final tracks = await answering(
      _itemWith([
        {'name': 'z.mp3', 'format': 'VBR MP3'},
        {'name': 'y.mp3', 'format': 'VBR MP3', 'track': '3/12'},
        {'name': 'b.mp3', 'format': 'VBR MP3'},
        {'name': 'x.mp3', 'format': 'VBR MP3', 'track': '1'},
      ]),
    ).tracks(_show);

    expect(tracks.map((track) => track.title), ['x', 'y', 'b', 'z']);
  });

  test('an item with no MP3 has no tracks', () async {
    final tracks = await answering(
      _itemWith([
        {'name': 'a.flac', 'format': 'Flac'},
      ]),
    ).tracks(_show);

    expect(tracks, isEmpty);
  });

  test('names with spaces, # and folders are encoded in the address', () async {
    final [track] =
        await answering(
          _itemWith([
            {'name': 'set 1/01 Iko #1 Iko.mp3', 'format': 'VBR MP3'},
          ]),
        ).tracks(
          const OnlineAlbum(
            source: OnlineSourceId.archive,
            id: 'gd77 x',
            title: 'Live',
            kind: OnlineAlbumKind.show,
          ),
        );

    expect(
      track.streamUrl.toString(),
      'https://archive.org/download/gd77%20x/set%201/01%20Iko%20%231%20Iko.mp3',
    );
    expect(track.title, '01 Iko #1 Iko');
  });

  test('failures are reported for both search and tracks', () async {
    await expectLater(
      source((_) => (status: 503, body: '')).search('x'),
      _fails(OnlineFailure.unavailable),
    );
    await expectLater(
      source((_) => throw const SocketException('no network')).tracks(_show),
      _fails(OnlineFailure.offline),
    );
    await expectLater(
      answering('<html>').tracks(_show),
      _fails(OnlineFailure.unavailable),
    );
  });
}
