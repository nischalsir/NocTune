import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/features/online/jamendo_source.dart';
import 'package:noctune/features/online/online_source.dart';

String _body({
  String status = 'success',
  int code = 0,
  String message = '',
  List<Map<String, Object?>> results = const [],
}) => jsonEncode({
  'headers': {
    'status': status,
    'code': code,
    'error_message': message,
    'results_count': results.length,
  },
  'results': results,
});

Map<String, Object?> _track({
  String id = '1204669',
  String name = 'Wanderer',
  Object? audio = 'https://prod-1.storage.jamendo.com/?trackid=1204669',
  bool downloadAllowed = true,
}) => {
  'id': id,
  'name': name,
  'duration': 227,
  'artist_name': 'Lena Orsa',
  'album_name': 'Night Roads',
  'album_image': 'https://usercontent.jamendo.com/?type=album&id=1',
  'image': 'https://usercontent.jamendo.com/?type=album&id=1',
  'audio': audio,
  'audiodownload':
      'https://prod-1.storage.jamendo.com/download/track/$id/mp32/',
  'audiodownload_allowed': downloadAllowed,
  'license_ccurl': 'http://creativecommons.org/licenses/by-sa/3.0/',
};

void main() {
  late List<Uri> asked;

  JamendoSource client(FutureOr<OnlineResponse> Function(Uri url) answer) =>
      JamendoSource(
        clientId: 'test-id',
        retryDelay: Duration.zero,
        fetch: (url) async {
          asked.add(url);
          return answer(url);
        },
      );

  setUp(() => asked = []);

  test('searches tracks with the client id and reads the results', () async {
    final results = await client(
      (_) => (status: 200, body: _body(results: [_track()])),
    ).search('  night roads ');

    final url = asked.single;
    expect(url.host, 'api.jamendo.com');
    expect(url.path, '/v3.0/tracks/');
    expect(url.queryParameters['client_id'], 'test-id');
    expect(url.queryParameters['search'], 'night roads');

    final track = results.single as OnlineTrack;
    expect(track.source, OnlineSourceId.jamendo);
    expect(track.id, '1204669');
    expect(track.title, 'Wanderer');
    expect(track.artist, 'Lena Orsa');
    expect(track.album, 'Night Roads');
    expect(track.duration, const Duration(seconds: 227));
    expect(track.streamUrl.host, 'prod-1.storage.jamendo.com');
    expect(track.downloadUrl, isNotNull);
    expect(track.imageUrl, isNotNull);
  });

  test('an empty answer is an empty list, not a failure', () async {
    expect(
      await client((_) => (status: 200, body: _body())).search('zzz'),
      isEmpty,
    );
  });

  test('tracks without a stream are left out', () async {
    final results = await client(
      (_) => (
        status: 200,
        body: _body(
          results: [
            _track(audio: ''),
            _track(id: '2', audio: null),
          ],
        ),
      ),
    ).search('x');

    expect(results, isEmpty);
  });

  test('no download link when Jamendo does not allow it', () async {
    final results = await client(
      (_) =>
          (status: 200, body: _body(results: [_track(downloadAllowed: false)])),
    ).search('x');

    expect((results.single as OnlineTrack).downloadUrl, isNull);
  });

  test('no connection is reported as offline', () async {
    final search = client(
      (_) => throw const SocketException('Failed host lookup'),
    ).search('x');

    await expectLater(
      search,
      throwsA(
        isA<OnlineSearchException>().having(
          (error) => error.failure,
          'failure',
          OnlineFailure.offline,
        ),
      ),
    );
  });

  test('a timeout is reported as offline', () async {
    await expectLater(
      client((_) => throw TimeoutException('slow')).search('x'),
      throwsA(
        isA<OnlineSearchException>().having(
          (error) => error.failure,
          'failure',
          OnlineFailure.offline,
        ),
      ),
    );
  });

  test('too many requests is reported as rate limited', () async {
    await expectLater(
      client((_) => (status: 429, body: '')).search('x'),
      throwsA(
        isA<OnlineSearchException>().having(
          (error) => error.failure,
          'failure',
          OnlineFailure.rateLimited,
        ),
      ),
    );
  });

  test('an error from Jamendo is reported with its message', () async {
    await expectLater(
      client(
        (_) => (
          status: 200,
          body: _body(
            status: 'failed',
            code: 5,
            message: 'Your credential is not authorized.',
          ),
        ),
      ).search('x'),
      throwsA(
        isA<OnlineSearchException>()
            .having(
              (error) => error.failure,
              'failure',
              OnlineFailure.unavailable,
            )
            .having(
              (error) => error.message,
              'message',
              contains('credential'),
            ),
      ),
    );
  });

  test('a server error or unreadable answer is unavailable', () async {
    for (final answer in [
      (status: 503, body: ''),
      (status: 200, body: '<html>'),
    ]) {
      await expectLater(
        client((_) => answer).search('x'),
        throwsA(
          isA<OnlineSearchException>().having(
            (error) => error.failure,
            'failure',
            OnlineFailure.unavailable,
          ),
        ),
      );
    }
  });

  test('a track survives being saved and read back', () async {
    final track =
        (await client((_) => (status: 200, body: _body(results: [_track()])))
                    .search('x'))
                .single
            as OnlineTrack;
    final copy = OnlineItem.fromJson(track.toJson()) as OnlineTrack;

    expect(copy.source, OnlineSourceId.jamendo);
    expect(copy.id, track.id);
    expect(copy.title, track.title);
    expect(copy.streamUrl, track.streamUrl);
    expect(copy.downloadUrl, track.downloadUrl);
    expect(copy.duration, track.duration);
  });

  test('asks once more when Jamendo answers with nothing', () async {
    var calls = 0;
    final results = await client((_) {
      calls++;
      return (status: 200, body: _body(results: calls == 1 ? [] : [_track()]));
    }).search('jazz');

    expect(calls, 2);
    expect(results, hasLength(1));
  });

  test('two empty answers are no match, not an error', () async {
    final results = await client((_) => (status: 200, body: _body()))
        .search('zzz');

    expect(asked, hasLength(2));
    expect(results, isEmpty);
  });

  test('old cached JSON without a source reads as Jamendo', () {
    final track = OnlineItem.fromJson({
      'id': '9',
      'title': 'Wanderer',
      'stream': 'https://prod-1.storage.jamendo.com/?trackid=9',
    }) as OnlineTrack;

    expect(track.source, OnlineSourceId.jamendo);
    expect(track.key, 'jamendo:9');
  });
}
