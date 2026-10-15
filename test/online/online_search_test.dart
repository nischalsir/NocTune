import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/features/online/jamendo_source.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:noctune/features/online/online_search.dart';
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

void main() {
  late SharedPreferences prefs;
  late OnlineResponse Function() answer;
  late int requests;

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
                  fetch: (_) async {
                    requests++;
                    return answer();
                  },
                )
              : null,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<OnlineResults?> search(ProviderContainer container, String query) {
    final subscription = container.listen(
      onlineSearchProvider(query),
      (_, _) {},
    );
    addTearDown(subscription.close);
    return container.read(onlineSearchProvider(query).future);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    requests = 0;
    answer = () => (status: 200, body: _found);
  });

  test('finds tracks on Jamendo', () async {
    final results = await search(container(), 'wanderer');

    expect(results!.tracks.single.title, 'Wanderer');
    expect(results.failure, isNull);
  });

  test('offline, the same search shows what it found last time', () async {
    await search(container(), 'Wanderer');

    answer = () => throw const SocketException('no network');
    final results = await search(container(), ' wanderer ');

    expect(results!.failure, OnlineFailure.offline);
    expect(results.fromCache, isTrue);
    expect(results.tracks.single.title, 'Wanderer');
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
    expect(requests, 0);
  });

  test('the cache keeps only the latest searches', () async {
    final cache = OnlineSearchCache(prefs);
    for (var i = 0; i < OnlineSearchCache.limit + 3; i++) {
      await cache.put('search $i', const []);
    }

    expect(cache.get('search 0'), isNull);
    expect(cache.get('search ${OnlineSearchCache.limit + 2}'), isEmpty);
  });
}
