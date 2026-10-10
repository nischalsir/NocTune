import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/playback/play_history_recorder.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LibraryRepository repository;
  late StreamController<MediaItem?> items;
  late StreamController<bool> playing;
  late PlayHistoryRecorder recorder;
  late Map<String, MediaItem> media;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = LibraryRepository(db);
    await repository.upsertTracks([
      for (final name in ['A', 'B'])
        Track(
          uri: '/music/$name.flac',
          fileName: '$name.flac',
          folder: '/music',
          title: name,
          dateAdded: DateTime(2026),
          dateModified: DateTime(2026),
        ),
    ]);
    media = {
      for (final track in await repository.tracks())
        track.title: mediaItemFromTrack(track),
    };
    items = StreamController<MediaItem?>();
    playing = StreamController<bool>();
    recorder = PlayHistoryRecorder(
      repository: repository,
      mediaItems: items.stream,
      playing: playing.stream,
    );
  });

  tearDown(() async {
    recorder.dispose();
    await db.close();
  });

  Future<Map<String, int>> counts() async {
    await pumpEventQueue();
    return {for (final t in await repository.tracks()) t.title: t.playCount};
  }

  test('counts a play when a track starts playing', () async {
    items.add(media['A']);
    playing.add(true);

    expect(await counts(), {'A': 1, 'B': 0});
  });

  test('does not count a track that is only cued up', () async {
    items.add(media['A']);
    playing.add(false);

    expect(await counts(), {'A': 0, 'B': 0});
  });

  test('pausing and resuming is still one play', () async {
    items.add(media['A']);
    playing.add(true);
    playing.add(false);
    playing.add(true);
    items.add(media['A']);

    expect(await counts(), {'A': 1, 'B': 0});
  });

  test('counts each track as the queue advances', () async {
    playing.add(true);
    items.add(media['A']);
    await pumpEventQueue();
    items.add(media['B']);
    await pumpEventQueue();
    items.add(media['A']);

    expect(await counts(), {'A': 2, 'B': 1});
    expect((await repository.recentlyPlayed()).first.title, 'A');
  });

  test('stores a length the player measured for an unmeasured file', () async {
    final item = media['A']!;
    expect(item.duration, isNull);

    items.add(item);
    items.add(item.copyWith(duration: const Duration(seconds: 215)));
    await pumpEventQueue();

    final track = (await repository.tracks()).first;
    expect(track.duration, const Duration(seconds: 215));
  });
}
