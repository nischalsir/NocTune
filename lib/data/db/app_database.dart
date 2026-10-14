import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens NocTune's on-device SQLite database and owns its schema.
abstract final class AppDatabase {
  static const _version = 5;

  /// Opens the database. Tests pass an in-memory [path] and an FFI [factory].
  static Future<Database> open({String? path, DatabaseFactory? factory}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), 'noctune.db');
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _migrate(db, from: 0),
        onUpgrade: (db, from, _) => _migrate(db, from: from),
      ),
    );
  }

  /// Applies every schema step after version [from], so a new install and an
  /// upgraded one end up identical.
  static Future<void> _migrate(Database db, {required int from}) async {
    if (from < 1) {
      await db.execute('''
        CREATE TABLE tracks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          uri TEXT NOT NULL UNIQUE,
          file_name TEXT NOT NULL,
          folder TEXT NOT NULL,
          title TEXT NOT NULL,
          artist TEXT,
          album TEXT,
          album_artist TEXT,
          genre TEXT,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          size_bytes INTEGER NOT NULL DEFAULT 0,
          codec TEXT,
          sample_rate INTEGER,
          bit_depth INTEGER,
          bitrate INTEGER,
          track_no INTEGER,
          disc_no INTEGER,
          year INTEGER,
          date_added INTEGER NOT NULL,
          date_modified INTEGER NOT NULL,
          art_path TEXT,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          play_count INTEGER NOT NULL DEFAULT 0,
          last_played_at INTEGER
        )
      ''');
      await db.execute('CREATE INDEX tracks_album ON tracks(album)');
      await db.execute('CREATE INDEX tracks_artist ON tracks(artist)');
      await db.execute('CREATE INDEX tracks_folder ON tracks(folder)');
      await db.execute('''
        CREATE TABLE playlists(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE playlist_tracks(
          playlist_id INTEGER NOT NULL
            REFERENCES playlists(id) ON DELETE CASCADE,
          track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
          position INTEGER NOT NULL,
          PRIMARY KEY(playlist_id, track_id)
        )
      ''');
    }
    if (from < 2) {
      // Which version of the tag reader last described each file. Raising the
      // reader's version makes the next scan re-read files it already knows,
      // which is how improved format detection reaches an existing library.
      await db.execute(
        'ALTER TABLE tracks ADD COLUMN reader_version INTEGER NOT NULL '
        'DEFAULT 1',
      );
      // Lyrics the user imported for a track. Lyrics embedded in the audio
      // file are read from the file itself and are not copied here.
      await db.execute('''
        CREATE TABLE lyrics(
          track_id INTEGER PRIMARY KEY
            REFERENCES tracks(id) ON DELETE CASCADE,
          content TEXT NOT NULL
        )
      ''');
    }
    if (from < 3) {
      // One row per time a track was played, which is what lets the home
      // screen group listening by day and rank it by period.
      await db.execute('''
        CREATE TABLE plays(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
          played_at INTEGER NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX plays_played_at ON plays(played_at)');
      // Earlier versions kept only each track's latest play; carry that one
      // over so the history isn't empty after the upgrade.
      await db.execute(
        'INSERT INTO plays(track_id, played_at) '
        'SELECT id, last_played_at FROM tracks '
        'WHERE last_played_at IS NOT NULL',
      );
    }
    if (from < 4) {
      // A picture the user chose as a playlist's cover, shown in place of
      // the covers of its tracks.
      await db.execute('ALTER TABLE playlists ADD COLUMN cover_path TEXT');
    }
    if (from < 5) {
      // Time actually spent listening to each track. Earlier versions only
      // estimated it, every play at the track's full length; that estimate
      // carries over as the starting amount.
      await db.execute(
        'ALTER TABLE tracks ADD COLUMN listened_ms INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'UPDATE tracks SET listened_ms = duration_ms * play_count',
      );
    }
  }
}
