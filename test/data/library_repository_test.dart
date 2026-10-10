import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track _track(
  String name, {
  String? artist,
  String? album,
  int durationSeconds = 180,
  int addedMs = 1000,
  int modifiedMs = 500,
  int sizeBytes = 1024,
}) => Track(
  uri: '/music/$name.flac',
  fileName: '$name.flac',
  folder: '/music',
  title: name,
  artist: artist,
  album: album,
  duration: Duration(seconds: durationSeconds),
  sizeBytes: sizeBytes,
  codec: 'flac',
  dateAdded: DateTime.fromMillisecondsSinceEpoch(addedMs),
  dateModified: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
);

void main() {
  late Database db;
  late LibraryRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = LibraryRepository(db);
  });

  tearDown(() => db.close());

  group('tracks', () {
    test('stores tracks and returns them sorted by title', () async {
      await repository.upsertTracks([_track('Zulu'), _track('alpha')]);

      final tracks = await repository.tracks();

      expect(tracks.map((t) => t.title), ['alpha', 'Zulu']);
      expect(tracks.every((t) => t.id > 0), isTrue);
    });

    test('sorts descending and by other columns', () async {
      await repository.upsertTracks([
        _track('Short', durationSeconds: 60, addedMs: 3000),
        _track('Long', durationSeconds: 600, addedMs: 1000),
      ]);

      final byDuration = await repository.tracks(
        sort: TrackSort.duration,
        ascending: false,
      );
      final byAdded = await repository.tracks(sort: TrackSort.dateAdded);

      expect(byDuration.first.title, 'Long');
      expect(byAdded.first.title, 'Long');
    });

    test('rescanning refreshes metadata but keeps user data', () async {
      await repository.upsertTracks([_track('Song', artist: 'Old')]);
      final id = (await repository.tracks()).single.id;
      await repository.setFavorite(id, favorite: true);
      await repository.recordPlay(id);

      await repository.upsertTracks([
        _track('Song', artist: 'New', addedMs: 9999),
      ]);

      final track = (await repository.tracks()).single;
      expect(track.id, id);
      expect(track.artist, 'New');
      expect(track.isFavorite, isTrue);
      expect(track.playCount, 1);
      expect(track.dateAdded.millisecondsSinceEpoch, 1000);
    });

    test('reports fingerprints for incremental scans', () async {
      await repository.upsertTracks([
        _track('Song', modifiedMs: 42, sizeBytes: 7),
      ]);

      final fingerprints = await repository.fingerprints();

      expect(fingerprints['/music/Song.flac'], (
        modifiedMs: 42,
        sizeBytes: 7,
        readerVersion: 1,
      ));
    });

    test('removes library entries by uri', () async {
      await repository.upsertTracks([_track('Keep'), _track('Drop')]);

      await repository.removeTracks(['/music/Drop.flac']);

      expect((await repository.tracks()).single.title, 'Keep');
    });

    test('searches title, artist, album and file name', () async {
      await repository.upsertTracks([
        _track('Midnight', artist: 'Aurora', album: 'Skyline'),
        _track('Daybreak', artist: 'Nova', album: 'Horizon'),
      ]);

      expect((await repository.search('midn')).single.title, 'Midnight');
      expect((await repository.search('nova')).single.title, 'Daybreak');
      expect((await repository.search('skyline')).single.title, 'Midnight');
      expect((await repository.search('.flac')), hasLength(2));
      expect(await repository.search('   '), isEmpty);
    });

    test('treats % and _ in a search as literal characters', () async {
      await repository.upsertTracks([_track('100% Pure'), _track('Plain')]);

      expect((await repository.search('%')).single.title, '100% Pure');
      expect(await repository.search('_'), isEmpty);
    });

    test('tracks favourites, play counts and recent plays', () async {
      await repository.upsertTracks([_track('A'), _track('B'), _track('C')]);
      final ids = {for (final t in await repository.tracks()) t.title: t.id};

      await repository.setFavorite(ids['B']!, favorite: true);
      await repository.recordPlay(ids['A']!, at: DateTime(2026, 1, 1));
      await repository.recordPlay(ids['C']!, at: DateTime(2026, 1, 2));
      await repository.recordPlay(ids['C']!, at: DateTime(2026, 1, 3));

      expect((await repository.favorites()).single.title, 'B');
      final recent = await repository.recentlyPlayed();
      expect(recent.map((t) => t.title), ['C', 'A']);
      expect(recent.first.playCount, 2);
    });

    test('summarises the library', () async {
      await repository.upsertTracks([
        _track('A', artist: 'X', album: 'One', durationSeconds: 100),
        _track('B', artist: 'X', album: 'Two', durationSeconds: 200),
      ]);

      final stats = await repository.stats();

      expect(stats.trackCount, 2);
      expect(stats.albumCount, 2);
      expect(stats.artistCount, 1);
      expect(stats.totalDuration, const Duration(seconds: 300));
    });

    test('announces every write', () async {
      var notifications = 0;
      final subscription = repository.changes.listen((_) => notifications++);

      await repository.upsertTracks([_track('A')]);
      await repository.createPlaylist('Mix');
      await pumpEventQueue();

      expect(notifications, 2);
      await subscription.cancel();
    });
  });

  group('browsing', () {
    setUp(
      () => repository.upsertTracks([
        _track('One', artist: 'Aurora', album: 'Skyline'),
        _track('Two', artist: 'Aurora', album: 'Skyline'),
        _track('Three', artist: 'Nova', album: 'Horizon'),
        _track('Loose'),
      ]),
    );

    test('groups tracks by album, with counts and an artist', () async {
      final albums = await repository.groups(TrackGroup.album);

      expect(albums.map((a) => a.name), ['Horizon', 'Skyline']);
      expect(albums.last.trackCount, 2);
      expect(albums.last.artist, 'Aurora');
    });

    test('leaves untagged tracks out of artist and genre groups', () async {
      final artists = await repository.groups(TrackGroup.artist);

      expect(artists.map((a) => a.name), ['Aurora', 'Nova']);
      expect(await repository.groups(TrackGroup.genre), isEmpty);
    });

    test('lists the tracks of one group', () async {
      final tracks = await repository.groupTracks(TrackGroup.album, 'Skyline');
      final folder = await repository.groupTracks(TrackGroup.folder, '/music');

      expect(tracks.map((t) => t.title), unorderedEquals(['One', 'Two']));
      expect(folder, hasLength(4));
    });

    test('loads tracks by id in the order asked, skipping missing', () async {
      final ids = {for (final t in await repository.tracks()) t.title: t.id};

      final tracks = await repository.tracksByIds([
        ids['Two']!,
        9999,
        ids['One']!,
      ]);

      expect(tracks.map((t) => t.title), ['Two', 'One']);
      expect((await repository.trackById(ids['Loose']!))!.title, 'Loose');
      expect(await repository.trackById(9999), isNull);
    });

    test('stores a measured duration', () async {
      final id = (await repository.tracks()).first.id;

      await repository.setDuration(id, const Duration(seconds: 99));

      expect(
        (await repository.trackById(id))!.duration,
        const Duration(seconds: 99),
      );
    });
  });

  group('duplicates', () {
    Track copy(
      String folder,
      String title, {
      String? artist,
      int seconds = 180,
    }) => Track(
      uri: '/$folder/$title.flac',
      fileName: '$title.flac',
      folder: '/$folder',
      title: title,
      artist: artist,
      duration: Duration(seconds: seconds),
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

    test('finds the same recording stored twice', () async {
      await repository.upsertTracks([
        copy('a', 'Song', artist: 'X'),
        copy('b', 'song', artist: 'x'),
        copy('a', 'Other', artist: 'X'),
      ]);

      final sets = await repository.duplicates();

      expect(sets, hasLength(1));
      expect(sets.single.map((t) => t.folder), unorderedEquals(['/a', '/b']));
    });

    test('does not confuse different versions or artists', () async {
      await repository.upsertTracks([
        copy('a', 'Song', artist: 'X', seconds: 180),
        copy('b', 'Song', artist: 'X', seconds: 320),
        copy('c', 'Song', artist: 'Y', seconds: 180),
      ]);

      expect(await repository.duplicates(), isEmpty);
    });
  });

  group('playlists', () {
    late Map<String, int> ids;

    setUp(() async {
      await repository.upsertTracks([_track('A'), _track('B'), _track('C')]);
      ids = {for (final t in await repository.tracks()) t.title: t.id};
    });

    test('keeps tracks in the order they were added', () async {
      final playlist = await repository.createPlaylist('Drive');
      await repository.addToPlaylist(playlist, ids['C']!);
      await repository.addToPlaylist(playlist, ids['A']!);
      await repository.addToPlaylist(playlist, ids['C']!);

      final tracks = await repository.playlistTracks(playlist);

      expect(tracks.map((t) => t.title), ['C', 'A']);
      expect((await repository.playlists()).single.trackCount, 2);
    });

    test('renames, removes tracks and deletes', () async {
      final playlist = await repository.createPlaylist('Old name');
      await repository.addToPlaylist(playlist, ids['A']!);
      await repository.addToPlaylist(playlist, ids['B']!);

      await repository.renamePlaylist(playlist, 'New name');
      await repository.removeFromPlaylist(playlist, ids['A']!);

      expect((await repository.playlists()).single.name, 'New name');
      expect((await repository.playlistTracks(playlist)).single.title, 'B');

      await repository.deletePlaylist(playlist);
      expect(await repository.playlists(), isEmpty);
      expect(await repository.tracks(), hasLength(3));
    });

    test('drops playlist entries when a track leaves the library', () async {
      final playlist = await repository.createPlaylist('Mix');
      await repository.addToPlaylist(playlist, ids['A']!);

      await repository.removeTracks(['/music/A.flac']);

      expect(await repository.playlistTracks(playlist), isEmpty);
    });
  });
}
