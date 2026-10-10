import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens NocTune's on-device SQLite database and owns its schema.
abstract final class AppDatabase {
  static const _version = 1;

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
        onCreate: _create,
      ),
    );
  }

  static Future<void> _create(Database db, int version) async {
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
        playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
        track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        PRIMARY KEY(playlist_id, track_id)
      )
    ''');
  }
}
