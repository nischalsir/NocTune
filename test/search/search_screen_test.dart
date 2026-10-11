import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';
import 'package:noctune/features/search/search_history.dart';
import 'package:noctune/features/search/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final played = <String>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int initialIndex = 0}) async =>
      played.add(tracks[initialIndex].title);
}

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

  Future<_FakeHandler> pump(
    WidgetTester tester, {
    List<String> remembered = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (remembered.isNotEmpty) 'search_history': remembered,
    });
    final preferences = await SharedPreferences.getInstance();
    final handler = _FakeHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
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
