import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/features/online/archive_source.dart';
import 'package:noctune/features/online/online_album.dart';
import 'package:noctune/features/online/online_search.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

OnlineAlbum _album(String id) => OnlineAlbum(
  source: OnlineSourceId.archive,
  id: id,
  title: 'Show $id',
  kind: OnlineAlbumKind.show,
);

final _item = jsonEncode({
  'files': [
    {'name': '01.Iko Iko.mp3', 'format': 'VBR MP3', 'track': '01'},
    {'name': '02.Might as Well.mp3', 'format': 'VBR MP3', 'track': '02'},
  ],
});

void main() {
  late SharedPreferences prefs;
  late OnlineResponse Function() answer;

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        archiveSourceProvider.overrideWithValue(
          ArchiveSource(fetch: (_) async => answer()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<OnlineResults> open(ProviderContainer container, OnlineAlbum album) {
    final subscription = container.listen(
      onlineAlbumProvider(album),
      (_, _) {},
    );
    addTearDown(subscription.close);
    return container.read(onlineAlbumProvider(album).future);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    answer = () => (status: 200, body: _item);
  });

  test('loads the tracks', () async {
    final results = await open(container(), _album('gd77'));

    expect(results.tracks.map((track) => track.title), [
      '01.Iko Iko',
      '02.Might as Well',
    ]);
    expect(results.failure, isNull);
  });

  test('offline, shows the tracks saved the last time it opened', () async {
    await open(container(), _album('gd77'));
    answer = () => throw const SocketException('no network');

    final results = await open(container(), _album('gd77'));

    expect(results.failure, OnlineFailure.offline);
    expect(results.fromCache, isTrue);
    expect(results.tracks, hasLength(2));
  });

  test('offline with nothing saved gives the failure and no tracks', () async {
    answer = () => throw const SocketException('no network');

    final results = await open(container(), _album('gd77'));

    expect(results.failure, OnlineFailure.offline);
    expect(results.fromCache, isFalse);
    expect(results.tracks, isEmpty);
  });

  test('keeps the last 20 albums', () async {
    for (var i = 0; i < 21; i++) {
      await open(container(), _album('show$i'));
    }
    answer = () => throw const SocketException('no network');

    expect((await open(container(), _album('show0'))).tracks, isEmpty);
    expect((await open(container(), _album('show1'))).tracks, hasLength(2));
    expect((await open(container(), _album('show20'))).tracks, hasLength(2));
  });
}
