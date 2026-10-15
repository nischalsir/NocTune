import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/features/online/archive_source.dart';
import 'package:noctune/features/online/audius_source.dart';
import 'package:noctune/features/online/jamendo_source.dart';
import 'package:noctune/features/online/online_search.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _found = jsonEncode({
  'headers': {'status': 'success', 'code': 0},
  'results': [
    {
      'id': '9',
      'name': 'Wanderer',
      'artist_name': 'Lena Orsa',
      'duration': 200,
      'audio': 'https://prod-1.storage.jamendo.com/?trackid=9',
    },
  ],
});

final _audius = File('test/online/fixtures/audius_search.json')
    .readAsStringSync();
final _archive = File('test/online/fixtures/archive_search.json')
    .readAsStringSync();

OnlineTrack _song(String id) => OnlineTrack(
  id: id,
  title: id,
  streamUrl: Uri.parse('https://example.org/$id'),
);

void main() {
  late SharedPreferences prefs;
  late OnlineResponse Function() answer;
  late Map<OnlineSourceId, int> requests;

  OnlineFetch counting(OnlineSourceId source, OnlineResponse Function() body) =>
      (_) async {
        requests[source] = (requests[source] ?? 0) + 1;
        return body();
      };

  ProviderContainer container({bool configured = true}) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        onlineSearchDelayProvider.overrideWithValue(Duration.zero),
        jamendoSourceProvider.overrideWithValue(
          configured
              ? JamendoSource(
                  clientId: 'id',
                  retryDelay: Duration.zero,
                  fetch: counting(OnlineSourceId.jamendo, () => answer()),
                )
              : null,
        ),
        audiusSourceProvider.overrideWithValue(
          AudiusSource(
            fetch: counting(
              OnlineSourceId.audius,
              () => (status: 200, body: _audius),
            ),
          ),
        ),
        archiveSourceProvider.overrideWithValue(
          ArchiveSource(
            fetch: counting(
              OnlineSourceId.archive,
              () => (status: 200, body: _archive),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<OnlineResults?> search(
    ProviderContainer container,
    String query, [
    OnlineSourceId source = OnlineSourceId.jamendo,
  ]) {
    final provider = onlineSourceSearchProvider((source, query));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    return container.read(provider.future);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests = {};
    answer = () => (status: 200, body: _found);
  });

  test('finds tracks on Jamendo', () async {
    final results = await search(container(), 'wanderer');

    expect(results!.tracks.single.title, 'Wanderer');
    expect(results.failure, isNull);
  });

  test('each source is searched on its own', () async {
    final scope = container();

    final audius = await search(scope, 'lofi', OnlineSourceId.audius);
    final archive = await search(scope, 'lofi', OnlineSourceId.archive);

    expect(audius!.items.first.source, OnlineSourceId.audius);
    expect(archive!.items.first, isA<OnlineAlbum>());
    expect(requests, {OnlineSourceId.audius: 1, OnlineSourceId.archive: 1});
  });

  test('offline, the same search shows what it found last time', () async {
    await search(container(), 'Wanderer');

    answer = () => throw const SocketException('no network');
    final results = await search(container(), ' wanderer ');

    expect(results!.failure, OnlineFailure.offline);
    expect(results.fromCache, isTrue);
    expect(results.tracks.single.title, 'Wanderer');
  });

  test('offline, a source falls back to its own saved results', () async {
    final cache = OnlineSearchCache(prefs);
    await cache.put(OnlineSourceId.audius, 'night', [
      _song('a').copyWithSource(OnlineSourceId.audius),
    ]);
    answer = () => throw const SocketException('no network');

    final results = await search(container(), 'night');

    expect(results!.failure, OnlineFailure.offline);
    expect(results.fromCache, isFalse);
    expect(results.items, isEmpty);
  });

  test(
    'a failure with nothing saved is an empty answer, not an error',
    () async {
      answer = () => (status: 429, body: '');

      final results = await search(container(), 'anything');

      expect(results!.failure, OnlineFailure.rateLimited);
      expect(results.tracks, isEmpty);
      expect(results.fromCache, isFalse);
    },
  );

  test('nothing is asked without a client id or with search off', () async {
    expect(await search(container(configured: false), 'wanderer'), isNull);

    final switchedOff = container();
    switchedOff.read(onlineSearchEnabledProvider.notifier).set(false);
    expect(await search(switchedOff, 'wanderer'), isNull);
    expect(await search(switchedOff, 'lofi', OnlineSourceId.audius), isNull);
    expect(requests, isEmpty);
  });

  test('a source switched off is not asked', () async {
    final scope = container();
    scope
        .read(onlineSourceEnabledProvider(OnlineSourceId.audius).notifier)
        .set(false);

    expect(await search(scope, 'lofi', OnlineSourceId.audius), isNull);
    expect(requests[OnlineSourceId.audius], isNull);
    expect(prefs.getBool('online_source_audius'), isFalse);
    expect(scope.read(onlineSourcesProvider).map((source) => source.id), [
      OnlineSourceId.jamendo,
      OnlineSourceId.archive,
    ]);
  });

  test('without a Jamendo id, Audius and Archive are still asked', () async {
    final scope = container(configured: false);

    expect(scope.read(onlineSourcesProvider).map((source) => source.id), [
      OnlineSourceId.audius,
      OnlineSourceId.archive,
    ]);
    expect(await search(scope, 'lofi', OnlineSourceId.audius), isNotNull);
  });

  test('main switch off asks no source', () {
    final scope = container();
    scope.read(onlineSearchEnabledProvider.notifier).set(false);

    expect(scope.read(onlineSourcesProvider), isEmpty);
  });

  test('the cache keeps 20 searches per source', () async {
    final cache = OnlineSearchCache(prefs);
    for (var i = 0; i < OnlineSearchCache.limit + 1; i++) {
      await cache.put(OnlineSourceId.jamendo, 'search $i', const []);
    }
    await cache.put(OnlineSourceId.audius, 'search 0', [
      _song('a').copyWithSource(OnlineSourceId.audius),
    ]);

    expect(cache.get(OnlineSourceId.jamendo, 'search 0'), isNull);
    expect(cache.get(OnlineSourceId.jamendo, 'search 1'), isEmpty);
    expect(cache.get(OnlineSourceId.jamendo, 'Search 20 '), isEmpty);
    expect(
      cache.get(OnlineSourceId.audius, 'search 0')!.single.key,
      'audius:a',
    );
  });

  test('the cache keeps albums as albums', () async {
    final cache = OnlineSearchCache(prefs);
    const show = OnlineAlbum(
      source: OnlineSourceId.archive,
      id: 'gd77',
      title: 'Live',
      kind: OnlineAlbumKind.show,
    );
    await cache.put(OnlineSourceId.archive, 'live', [show]);

    expect(cache.get(OnlineSourceId.archive, 'live'), [show]);
  });

  test('the old cache key is removed', () async {
    await prefs.setString('online_search_cache', '{}');

    OnlineSearchCache(prefs).get(OnlineSourceId.jamendo, 'x');

    expect(prefs.containsKey('online_search_cache'), isFalse);
  });

  test('interleaves sources, first of each, then second of each', () {
    final [a1, a2, a3, b1, c1, c2] = [
      for (final id in ['a1', 'a2', 'a3', 'b1', 'c1', 'c2']) _song(id),
    ];

    expect(
      interleave([
        [a1, a2, a3],
        [b1],
        [],
        [c1, c2],
      ]).map((item) => item.id),
      ['a1', 'b1', 'c1', 'a2', 'c2', 'a3'],
    );
  });
}

extension on OnlineTrack {
  OnlineTrack copyWithSource(OnlineSourceId source) =>
      OnlineTrack(source: source, id: id, title: title, streamUrl: streamUrl);
}
