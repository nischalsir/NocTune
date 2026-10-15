import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/online/audius_source.dart';
import 'package:noctune/features/online/online_source.dart';

/// A real answer to a search, trimmed to four tracks: one that plays, one
/// Audius won't stream, one locked to paying fans, and one free to download.
final _fixture = File('test/online/fixtures/audius_search.json')
    .readAsStringSync();

Matcher _fails(OnlineFailure failure) => throwsA(
  isA<OnlineSearchException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

void main() {
  late List<Uri> asked;

  AudiusSource source(FutureOr<OnlineResponse> Function(Uri url) answer) =>
      AudiusSource(
        fetch: (url) async {
          asked.add(url);
          return answer(url);
        },
      );

  AudiusSource answering(String body) =>
      source((_) => (status: 200, body: body));

  setUp(() => asked = []);

  test('searches with the app name and keeps only playable tracks', () async {
    final results = await answering(_fixture).search(' lofi ');

    final url = asked.single;
    expect(
      url.toString(),
      startsWith('https://api.audius.co/v1/tracks/search'),
    );
    expect(url.queryParameters, {
      'query': 'lofi',
      'app_name': 'NocTune',
      'limit': '20',
    });
    expect(results.map((track) => track.id), ['YmJWK', 'KlK59']);
  });

  test('plays from the stable stream address', () async {
    final track =
        (await answering(_fixture).search('lofi')).first as OnlineTrack;

    expect(track.source, OnlineSourceId.audius);
    expect(track.key, 'audius:YmJWK');
    expect(track.title, 'kirbytape mix vol. 13 - lofi house edition');
    expect(track.artist, 'omgkirby');
    expect(track.duration, const Duration(seconds: 1690));
    expect(
      track.streamUrl.toString(),
      'https://api.audius.co/v1/tracks/YmJWK/stream?app_name=NocTune',
    );
    expect(
      track.imageUrl.toString(),
      'https://val006.open-audio-validator.com/content/'
      'QmPHYjy9G8XDH6izXRJeBU7zD3NEeyuh6vap2cATvkisfu/480x480.jpg',
    );
  });

  test('download address only when the artist allows it', () async {
    final [plain, free] = (await answering(_fixture).search('lofi'))
        .cast<OnlineTrack>();

    expect(plain.downloadUrl, isNull);
    expect(
      free.downloadUrl.toString(),
      'https://api.audius.co/v1/tracks/KlK59/download?app_name=NocTune',
    );
  });

  test('no match is an empty list', () async {
    expect(await answering('{"data": []}').search('zzz'), isEmpty);
  });

  test('too many requests is rate limited', () async {
    await expectLater(
      source((_) => (status: 429, body: '')).search('x'),
      _fails(OnlineFailure.rateLimited),
    );
  });

  test('a server error or unreadable answer is unavailable', () async {
    await expectLater(
      source((_) => (status: 500, body: '')).search('x'),
      _fails(OnlineFailure.unavailable),
    );
    await expectLater(
      answering('<html>').search('x'),
      _fails(OnlineFailure.unavailable),
    );
  });

  test('no connection is offline', () async {
    await expectLater(
      source((_) => throw const SocketException('no network')).search('x'),
      _fails(OnlineFailure.offline),
    );
  });
}
