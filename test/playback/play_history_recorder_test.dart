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
  late DateTime now;

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
    now = DateTime(2026, 10, 14, 9);
    recorder = PlayHistoryRecorder(
      repository: repository,
      mediaItems: items.stream,
      playing: playing.stream,
      now: () => now,
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

  test('playing on the track the last session was partway through is not '
      'another play', () async {
    recorder.dispose();
    items = StreamController<MediaItem?>();
    playing = StreamController<bool>();
    final restored = media['A']!.extras![kTrackIdExtra] as int;
    recorder = PlayHistoryRecorder(
      repository: repository,
      mediaItems: items.stream,
      playing: playing.stream,
      resumedTrackId: restored,
      now: () => now,
    );

    // Launch: the track comes back paused, then the user presses play.
    items.add(media['A']);
    playing.add(false);
    await pumpEventQueue();
    playing.add(true);
    expect(await counts(), {'A': 0, 'B': 0});

    // Moving on and coming back to it later is a new play.
    items.add(media['B']);
    await pumpEventQueue();
    items.add(media['A']);
    expect(await counts(), {'A': 1, 'B': 1});
  });

  Future<Duration> listened() async {
    await pumpEventQueue();
    return (await repository.stats()).listenedDuration;
  }

  test('adds only the time listened when a track is skipped', () async {
    items.add(media['A']);
    playing.add(true);
    await pumpEventQueue();
    now = now.add(const Duration(seconds: 40));
    items.add(media['B']);

    expect(await listened(), const Duration(seconds: 40));
  });

  test('pausing and resuming adds each stretch once', () async {
    items.add(media['A']);
    playing.add(true);
    await pumpEventQueue();
    now = now.add(const Duration(seconds: 30));
    playing.add(false);
    await pumpEventQueue();
    // Time spent paused is not listening.
    now = now.add(const Duration(minutes: 5));
    playing.add(true);
    await pumpEventQueue();
    now = now.add(const Duration(seconds: 20));
    expect(recorder.unsaved, const Duration(seconds: 20));
    playing.add(false);

    expect(await listened(), const Duration(seconds: 50));
    expect(recorder.unsaved, Duration.zero);
  });

  test('a track only cued up adds no listening time', () async {
    items.add(media['A']);
    playing.add(false);
    await pumpEventQueue();
    now = now.add(const Duration(minutes: 3));
    items.add(media['B']);

    expect(await listened(), Duration.zero);
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
