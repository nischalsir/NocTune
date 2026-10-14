import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/core/theme/noc_palette.dart';
import 'package:noctune/core/theme/noc_theme.dart';
import 'package:noctune/core/widgets/pill_button.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/delete_track.dart';
import 'package:noctune/features/library/track_menu.dart';
import 'package:noctune/features/playback/noc_audio_handler.dart';

class _FakeHandler extends Fake implements NocAudioHandler {
  final unqueued = <String>[];

  @override
  Future<void> removeTrack(Track track) async => unqueued.add(track.title);
}

class _FakeRepository extends Fake implements LibraryRepository {
  final forgotten = <String>[];

  @override
  Future<void> removeTracks(Iterable<String> uris) async =>
      forgotten.addAll(uris);
}

final _song = Track(
  id: 7,
  uri: '/storage/emulated/0/Music/Low Tide.m4a',
  fileName: 'Low Tide.m4a',
  folder: '/storage/emulated/0/Music',
  title: 'Low Tide',
  artist: 'Marlowe',
  album: 'Tidewater',
  duration: const Duration(minutes: 4),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

Future<(_FakeHandler, _FakeRepository, List<Track> asked)> _openMenu(
  WidgetTester tester, {
  required Future<bool> Function(Track track) deleter,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final handler = _FakeHandler();
  final repository = _FakeRepository();
  final asked = <Track>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        libraryRepositoryProvider.overrideWithValue(repository),
        trackFileDeleterProvider.overrideWithValue((track) {
          asked.add(track);
          return deleter(track);
        }),
      ],
      child: MaterialApp(
        theme: buildNocTheme(Brightness.dark, NocAccent.red),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showTrackMenu(context, ref, _song),
              child: const Text('menu'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('menu'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Delete from device'));
  await tester.tap(find.text('Delete from device'));
  await tester.pumpAndSettle();
  return (handler, repository, asked);
}

void main() {
  testWidgets('asks first, and Cancel leaves everything as it was', (
    tester,
  ) async {
    final (handler, repository, asked) = await _openMenu(
      tester,
      deleter: (_) async => true,
    );

    expect(find.text('Delete this song?'), findsOneWidget);
    expect(find.textContaining('Low Tide'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(asked, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(repository.forgotten, isEmpty);
    expect(handler.unqueued, isEmpty);
  });

  testWidgets(
    'Delete removes the file, the library entry and the queue entry',
    (tester) async {
      final (handler, repository, asked) = await _openMenu(
        tester,
        deleter: (_) async => true,
      );

      await tester.tap(find.widgetWithText(PillButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(asked.single.uri, _song.uri);
      expect(repository.forgotten, [_song.uri]);
      expect(handler.unqueued, ['Low Tide']);
      expect(find.text('Deleted Low Tide'), findsOneWidget);
    },
  );

  testWidgets("keeps the song when the phone's own question is answered no", (
    tester,
  ) async {
    final (handler, repository, asked) = await _openMenu(
      tester,
      deleter: (_) async => false,
    );

    await tester.tap(find.widgetWithText(PillButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(asked, hasLength(1));
    expect(repository.forgotten, isEmpty);
    expect(handler.unqueued, isEmpty);
    expect(find.text('Deleted Low Tide'), findsNothing);
  });

  testWidgets('says why when the file cannot be deleted, and keeps the song', (
    tester,
  ) async {
    final (handler, repository, _) = await _openMenu(
      tester,
      deleter: (_) async =>
          throw const DeleteFailed('Deleting needs Android 11 or later.'),
    );

    await tester.tap(find.widgetWithText(PillButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        "Couldn't delete Low Tide. Deleting needs Android 11 or later.",
      ),
      findsOneWidget,
    );
    expect(repository.forgotten, isEmpty);
    expect(handler.unqueued, isEmpty);
  });
}
