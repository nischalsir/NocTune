import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/online/archive_source.dart';
import 'package:noctune/features/online/audius_source.dart';
import 'package:noctune/features/online/external_search.dart';
import 'package:noctune/features/online/jamendo_source.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:noctune/features/online/online_playback.dart';
import 'package:noctune/features/online/online_search.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/search/search_history.dart';
import 'package:noctune/features/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final played = <String>[];
  final playedUris = <String>[];

  /// The titles queued by the last play.
  List<String> queued = [];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async {
    played.add(tracks[initialIndex].title);
    playedUris.add(tracks[initialIndex].uri);
    queued = [for (final track in tracks) track.title];
  }
}

/// Never asked: nothing in these tests is downloaded.
class _Repository extends Fake implements LibraryRepository {}

/// Jamendo's answer with one track per title.
OnlineResponse _jamendo(List<String> titles) => (
  status: 200,
  body: jsonEncode({
    'headers': {'status': 'success', 'code': 0},
    'results': [
      for (final (index, title) in titles.indexed)
        {
          'id': '${index + 1}',
          'name': title,
          'artist_name': 'Lena Orsa',
          'duration': 180,
          'audio': 'https://prod-1.storage.jamendo.com/?trackid=${index + 1}',
          'audiodownload':
              'https://prod-1.storage.jamendo.com/download/${index + 1}',
          'audiodownload_allowed': true,
        },
    ],
  }),
);

/// Audius's answer with one streamable track per title.
OnlineResponse _audius(List<String> titles) => (
  status: 200,
  body: jsonEncode({
    'data': [
      for (final (index, title) in titles.indexed)
        {
          'id': 'a$index',
          'title': title,
          'duration': 120,
          'user': {'name': 'Beatmaker'},
          'is_streamable': true,
          'is_downloadable': false,
        },
    ],
  }),
);

/// The Internet Archive's answer with one show per title.
OnlineResponse _archive(List<String> titles) => (
  status: 200,
  body: jsonEncode({
    'response': {
      'docs': [
        for (final (index, title) in titles.indexed)
          {
            'identifier': 'show$index',
            'title': title,
            'creator': 'Mars Hotel',
            'mediatype': 'etree',
          },
      ],
    },
  }),
);

Track _track(int id, String title) => Track(
  id: id,
  uri: '/music/$title.flac',
  fileName: '$title.flac',
  folder: '/music',
  title: title,
  artist: 'Aurora',
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

void main() {
  final library = [_track(1, 'Aashish'), _track(2, 'Balenci')];

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('noctune_search'));
  tearDown(() => root.deleteSync(recursive: true));

  late List<Uri> opened;

  /// [jamendo], [audius] and [archive] answer online searches. Without
  /// [jamendo] the build has no Jamendo client id, as by default; without
  /// [audius] or [archive] that source is switched off, so tests never go
  /// online. [opens] says whether a link opens.
  Future<_FakeHandler> pump(
    WidgetTester tester, {
    List<String> remembered = const [],
    OnlineFetch? jamendo,
    OnlineFetch? audius,
    OnlineFetch? archive,
    bool Function(Uri url)? opens,
    Map<String, Object> cached = const {},
  }) async {
    opened = [];
    SharedPreferences.setMockInitialValues({
      if (remembered.isNotEmpty) 'search_history': remembered,
      if (audius == null) 'online_source_audius': false,
      if (archive == null) 'online_source_archive': false,
      ...cached,
    });
    final preferences = await SharedPreferences.getInstance();
    final handler = _FakeHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appPathsProvider.overrideWithValue((
            artworkDir: '${root.path}/artwork',
            musicDir: '${root.path}/music',
            coverDir: '${root.path}/covers',
          )),
          onlineSearchDelayProvider.overrideWithValue(Duration.zero),
          libraryRepositoryProvider.overrideWithValue(_Repository()),
          jamendoSourceProvider.overrideWithValue(
            jamendo == null
                ? null
                : JamendoSource(
                    clientId: 'test',
                    retryDelay: Duration.zero,
                    fetch: jamendo,
                  ),
          ),
          audiusSourceProvider.overrideWithValue(
            AudiusSource(
              fetch: audius ?? (_) async => throw StateError('not asked'),
            ),
          ),
          archiveSourceProvider.overrideWithValue(
            ArchiveSource(
              fetch: archive ?? (_) async => throw StateError('not asked'),
            ),
          ),
          linkOpenerProvider.overrideWithValue((url) async {
            opened.add(url);
            return opens?.call(url) ?? true;
          }),
          // Covers are not fetched in tests.
          fileFetcherProvider.overrideWithValue(
            (url, target) async => throw const SocketException('test'),
          ),
          audioHandlerProvider.overrideWithValue(handler),
          currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
          searchResultsProvider.overrideWith(
            (ref, query) => [
              for (final track in library)
                if (track.title.toLowerCase().contains(query.toLowerCase()))
                  track,
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildNocTheme(Brightness.dark, NocAccent.red),
          home: const Scaffold(body: SearchScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return handler;
  }

  Future<List<String>?> saved() async =>
      (await SharedPreferences.getInstance()).getStringList('search_history');

  testWidgets('with nothing searched yet it says what it searches', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Search your library'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);
  });

  testWidgets('typing alone is not remembered; sending the search is', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'bal');
    await tester.pumpAndSettle();
    expect(find.text('Balenci'), findsOneWidget);
    expect(await saved(), isNull);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(await saved(), ['bal']);
  });

  testWidgets('playing a result remembers the search that found it', (
    tester,
  ) async {
    final handler = await pump(tester);

    await tester.enterText(find.byType(TextField), 'aash');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aashish'));
    await tester.pumpAndSettle();

    expect(handler.played, ['Aashish']);
    expect(await saved(), ['aash']);
  });

  testWidgets('lists recent searches, and a tap runs one again', (
    tester,
  ) async {
    await pump(tester, remembered: ['bal', 'aash']);

    expect(find.text('Recent searches'), findsOneWidget);
    // Newest first.
    expect(
      tester.getTopLeft(find.text('bal')).dy,
      lessThan(tester.getTopLeft(find.text('aash')).dy),
    );

    await tester.tap(find.text('aash'));
    await tester.pumpAndSettle();

    expect(find.text('Aashish'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'aash',
    );
    // It moves to the top rather than being listed twice.
    expect(await saved(), ['aash', 'bal']);
  });

  testWidgets('Clear empties the list', (tester) async {
    await pump(tester, remembered: ['bal']);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Recent searches'), findsNothing);
    expect(find.text('Search your library'), findsOneWidget);
    expect(await saved(), isEmpty);
  });

  group('with Jamendo', () {
    testWidgets('shows the library and Jamendo together', (tester) async {
      await pump(tester, jamendo: (_) async => _jamendo(['Balenci Live']));

      await tester.enterText(find.byType(TextField), 'bal');
      await tester.pumpAndSettle();

      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Balenci'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('JAMENDO'), findsOneWidget);
      expect(find.text('Balenci Live'), findsOneWidget);
      expect(find.byTooltip('Download Balenci Live'), findsOneWidget);
    });

    testWidgets('tapping a Jamendo result streams it', (tester) async {
      final handler = await pump(
        tester,
        jamendo: (_) async => _jamendo(['Balenci Live']),
      );

      await tester.enterText(find.byType(TextField), 'bal');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Balenci Live'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(handler.played, ['Balenci Live']);
      expect(handler.playedUris.single, startsWith('https://prod-1.'));
      expect(await saved(), ['bal']);
    });

    testWidgets('Jamendo failing leaves the library results', (tester) async {
      await pump(tester, jamendo: (_) async => (status: 429, body: ''));

      await tester.enterText(find.byType(TextField), 'bal');
      await tester.pumpAndSettle();

      expect(find.text('Balenci'), findsOneWidget);
      expect(
        find.text('Jamendo is busy right now. Try again in a minute.'),
        findsOneWidget,
      );
    });

    testWidgets('a Jamendo error page or bad answer does not break the page', (
      tester,
    ) async {
      await pump(tester, jamendo: (_) async => (status: 200, body: '<html>'));

      await tester.enterText(find.byType(TextField), 'bal');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Balenci'), findsOneWidget);
      expect(
        find.text("Jamendo couldn't be reached right now."),
        findsOneWidget,
      );
    });

    testWidgets('offline, saved results are marked and not started', (
      tester,
    ) async {
      final handler = await pump(
        tester,
        jamendo: (_) async => throw const SocketException('offline'),
        cached: {
          'online_search_cache_v2': jsonEncode({
            'jamendo:night': [
              OnlineTrack(
                id: '1',
                title: 'Night Drive',
                artist: 'Lena Orsa',
                streamUrl: Uri.parse(
                  'https://prod-1.storage.jamendo.com/?trackid=1',
                ),
                downloadUrl: Uri.parse(
                  'https://prod-1.storage.jamendo.com/download/1',
                ),
              ).toJson(),
            ],
          }),
        },
      );

      await tester.enterText(find.byType(TextField), 'night');
      await tester.pumpAndSettle();

      expect(find.textContaining("You're offline."), findsOneWidget);
      expect(find.text('Night Drive'), findsOneWidget);
      expect(find.byTooltip('Needs an internet connection'), findsOneWidget);

      await tester.tap(find.text('Night Drive'));
      await tester.pumpAndSettle();

      expect(handler.played, isEmpty);
      expect(
        find.textContaining('needs an internet connection'),
        findsOneWidget,
      );
    });

    testWidgets('offline with nothing saved says so', (tester) async {
      await pump(
        tester,
        jamendo: (_) async => throw const SocketException('offline'),
      );

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('Online results appear once'), findsOneWidget);
    });
  });

  group('with several sources', () {
    testWidgets('mixes the sources in turn with their badges', (tester) async {
      await pump(
        tester,
        jamendo: (_) async => _jamendo(['J1', 'J2']),
        audius: (_) async => _audius(['A1']),
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();

      final y = [
        for (final title in ['J1', 'A1', 'J2'])
          tester.getTopLeft(find.text(title)).dy,
      ];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('JAMENDO'), findsNWidgets(2));
      expect(find.text('AUDIUS'), findsOneWidget);
    });

    testWidgets('one source failing still shows and plays the others', (
      tester,
    ) async {
      final handler = await pump(
        tester,
        jamendo: (_) async => _jamendo(['J1']),
        audius: (_) async => (status: 500, body: ''),
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(
        find.text("Audius couldn't be reached right now."),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('J1'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(handler.played, ['J1']);
    });

    testWidgets('one source offline does not stop the others', (tester) async {
      final handler = await pump(
        tester,
        jamendo: (_) async => _jamendo(['J1']),
        audius: (_) async => throw const SocketException('blocked'),
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(find.textContaining("You're offline."), findsNothing);
      expect(
        find.text("Audius couldn't be reached right now."),
        findsOneWidget,
      );
      expect(find.byTooltip('Needs an internet connection'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text('J1'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(handler.played, ['J1']);
    });

    testWidgets('a source that fails unexpectedly says so', (tester) async {
      await pump(
        tester,
        jamendo: (_) async => _jamendo(['J1']),
        audius: (_) async => throw ArgumentError('surprise'),
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();

      expect(find.text('J1'), findsOneWidget);
      expect(
        find.text("Audius couldn't be reached right now."),
        findsOneWidget,
      );
    });

    testWidgets('tapping a song queues only the songs', (tester) async {
      final handler = await pump(
        tester,
        jamendo: (_) async => _jamendo(['J1']),
        audius: (_) async => _audius(['A1']),
        archive: (_) async => _archive(['Live Show']),
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(find.text('Live Show'), findsOneWidget);
      expect(find.text('ARCHIVE'), findsOneWidget);
      expect(find.text('Mars Hotel · show'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('A1'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(handler.played, ['A1']);
      expect(handler.queued, ['J1', 'A1']);
    });

    testWidgets('the Spotify button tries the app, then the website', (
      tester,
    ) async {
      await pump(tester, opens: (url) => url.scheme != 'spotify');

      await tester.enterText(find.byType(TextField), 'love song');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search on Spotify'));
      await tester.pumpAndSettle();

      expect(opened.map((url) => '$url'), [
        'spotify:search:love%20song',
        'https://open.spotify.com/search/love%20song',
      ]);
    });

    testWidgets('the YouTube Music button opens its search', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'love song');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search on YouTube Music'));
      await tester.pumpAndSettle();

      final url = opened.single;
      expect(url.host, 'music.youtube.com');
      expect(url.path, '/search');
      expect(url.queryParameters['q'], 'love song');
    });

    testWidgets('the buttons show even when nothing matches', (tester) async {
      await pump(tester, jamendo: (_) async => _jamendo([]));

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing in your library or online matches "zzz".'),
        findsOneWidget,
      );
      expect(find.text('Search on Spotify'), findsOneWidget);
      expect(find.text('Search on YouTube Music'), findsOneWidget);
    });

    testWidgets('a link that does not open says so', (tester) async {
      await pump(tester, opens: (_) => false);

      await tester.enterText(find.byType(TextField), 'love');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search on Spotify'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't open Spotify."), findsOneWidget);
    });
  });

  group('the history', () {
    Future<ProviderContainer> container(List<String> remembered) async {
      SharedPreferences.setMockInitialValues({'search_history': remembered});
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('lists a repeated search once, whatever its capitals', () async {
      final history = await container(['Drake', 'aujla']);

      history.read(searchHistoryProvider.notifier).add('  drake ');

      expect(history.read(searchHistoryProvider), ['drake', 'aujla']);
    });

    test('ignores an empty search', () async {
      final history = await container(['aujla']);

      history.read(searchHistoryProvider.notifier).add('   ');

      expect(history.read(searchHistoryProvider), ['aujla']);
    });

    test('keeps only the latest ten', () async {
      final history = await container([
        for (var i = 0; i < SearchHistory.limit; i++) 'search $i',
      ]);

      history.read(searchHistoryProvider.notifier).add('newest');

      final kept = history.read(searchHistoryProvider);
      expect(kept, hasLength(SearchHistory.limit));
      expect(kept.first, 'newest');
      expect(kept, isNot(contains('search 9')));
    });
  });
}
