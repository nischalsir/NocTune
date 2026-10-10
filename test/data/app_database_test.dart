import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('upgrades a version 1 library without losing anything', () async {
    // The first released schema, with a track the user has favourited.
    final path = '${Directory.systemTemp.createTempSync('noctune_db').path}/v1';
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE tracks(
              id INTEGER PRIMARY KEY AUTOINCREMENT, uri TEXT NOT NULL UNIQUE,
              file_name TEXT NOT NULL, folder TEXT NOT NULL,
              title TEXT NOT NULL, artist TEXT, album TEXT, album_artist TEXT,
              genre TEXT, duration_ms INTEGER NOT NULL DEFAULT 0,
              size_bytes INTEGER NOT NULL DEFAULT 0, codec TEXT,
              sample_rate INTEGER, bit_depth INTEGER, bitrate INTEGER,
              track_no INTEGER, disc_no INTEGER, year INTEGER,
              date_added INTEGER NOT NULL, date_modified INTEGER NOT NULL,
              art_path TEXT, is_favorite INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0, last_played_at INTEGER)
          ''');
          await db.execute(
            'CREATE TABLE playlists(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'name TEXT NOT NULL, created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE playlist_tracks(playlist_id INTEGER NOT NULL, '
            'track_id INTEGER NOT NULL, position INTEGER NOT NULL, '
            'PRIMARY KEY(playlist_id, track_id))',
          );
          await db.insert('tracks', {
            'uri': '/music/a.flac',
            'file_name': 'a.flac',
            'folder': '/music',
            'title': 'Kept',
            'codec': 'flac',
            'date_added': 1,
            'date_modified': 2,
            'size_bytes': 3,
            'is_favorite': 1,
            'play_count': 4,
          });
        },
      ),
    );
    await old.close();

    final db = await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    final repository = LibraryRepository(db);

    final track = (await repository.tracks()).single;
    expect(track.title, 'Kept');
    expect(track.isFavorite, isTrue);
    expect(track.playCount, 4);
    // Existing rows are marked as read by the old reader, so the next scan
    // re-reads them with the new format checks.
    expect((await repository.fingerprints())['/music/a.flac'], (
      modifiedMs: 2,
      sizeBytes: 3,
      readerVersion: 1,
    ));

    // The lyrics table exists and follows its track.
    await repository.setImportedLyrics(track.id, '[00:01.00]Hello');
    expect(await repository.importedLyrics(track.id), '[00:01.00]Hello');
    await repository.removeTracks(['/music/a.flac']);
    expect(await repository.importedLyrics(track.id), isNull);
    await db.close();
  });

  test('a new install gets the same schema', () async {
    final db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    final repository = LibraryRepository(db);
    await repository.upsertTracks([
      Track(
        uri: '/music/a.flac',
        fileName: 'a.flac',
        folder: '/music',
        title: 'A',
        dateAdded: DateTime(2026),
        dateModified: DateTime.fromMillisecondsSinceEpoch(9),
      ),
    ], readerVersion: 2);

    expect((await repository.fingerprints()).values.single.readerVersion, 2);
    final id = (await repository.tracks()).single.id;
    await repository.setImportedLyrics(id, 'first');
    await repository.setImportedLyrics(id, 'second');
    expect(await repository.importedLyrics(id), 'second');
    await repository.removeImportedLyrics(id);
    expect(await repository.importedLyrics(id), isNull);
    await db.close();
  });
}
