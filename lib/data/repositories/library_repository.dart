import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../models/playlist.dart';
import '../models/track.dart';

/// Ways the track list can be ordered.
enum TrackSort {
  title('Title', 'title COLLATE NOCASE'),
  artist('Artist', 'artist COLLATE NOCASE'),
  album('Album', 'album COLLATE NOCASE, disc_no, track_no'),
  dateAdded('Date added', 'date_added'),
  duration('Duration', 'duration_ms'),
  fileName('File name', 'file_name COLLATE NOCASE');

  const TrackSort(this.label, this._orderBy);

  final String label;
  final String _orderBy;
}

/// Ways tracks can be grouped for browsing.
enum TrackGroup {
  album('album', 'disc_no, track_no, title COLLATE NOCASE'),
  artist('artist', 'album COLLATE NOCASE, disc_no, track_no'),
  genre('genre', 'title COLLATE NOCASE'),
  folder('folder', 'file_name COLLATE NOCASE');

  const TrackGroup(this._column, this._trackOrder);

  final String _column;
  final String _trackOrder;
}

/// What a previous scan recorded about a file, used to skip unchanged files.
typedef FileFingerprint = ({int modifiedMs, int sizeBytes, int readerVersion});

/// Reads and writes the local library: tracks, favourites, play history and
/// playlists. Original audio files are never touched.
class LibraryRepository {
  LibraryRepository(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  /// Fires after every write, so listeners can re-query.
  Stream<void> get changes => _changes.stream;

  // ---- Tracks ----

  /// Inserts new tracks and refreshes the file metadata of known ones,
  /// leaving favourites, play counts and the date added alone.
  ///
  /// [readerVersion] records which version of the tag reader produced them.
  Future<void> upsertTracks(List<Track> tracks, {int readerVersion = 1}) async {
    if (tracks.isEmpty) return;
    final batch = _db.batch();
    for (final track in tracks) {
      final row = {...track.toMetadataRow(), 'reader_version': readerVersion};
      // Insert-or-ignore then update, rather than SQL UPSERT, because the
      // system SQLite on Android 10 and older predates UPSERT.
      batch.insert('tracks', {
        ...row,
        'date_added': track.dateAdded.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.update('tracks', row, where: 'uri = ?', whereArgs: [track.uri]);
    }
    await batch.commit(noResult: true);
    _changes.add(null);
  }

  /// Every known file's fingerprint, keyed by URI.
  Future<Map<String, FileFingerprint>> fingerprints() async {
    final rows = await _db.query(
      'tracks',
      columns: ['uri', 'date_modified', 'size_bytes', 'reader_version'],
    );
    return {
      for (final row in rows)
        row['uri']! as String: (
          modifiedMs: row['date_modified']! as int,
          sizeBytes: row['size_bytes']! as int,
          readerVersion: row['reader_version']! as int,
        ),
    };
  }

  /// Forgets library entries by URI. The audio files themselves are not deleted.
  Future<void> removeTracks(Iterable<String> uris) async {
    final batch = _db.batch();
    for (final uri in uris) {
      batch.delete('tracks', where: 'uri = ?', whereArgs: [uri]);
    }
    await batch.commit(noResult: true);
    _changes.add(null);
  }

  Future<List<Track>> tracks({
    TrackSort sort = TrackSort.title,
    bool ascending = true,
  }) => _queryTracks(orderBy: _order(sort, ascending));

  /// Matches the query against title, artist, album and file name.
  Future<List<Track>> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return Future.value(const []);
    final escaped = trimmed.replaceAllMapped(
      RegExp(r'[\\%_]'),
      (match) => '\\${match[0]}',
    );
    final pattern = '%$escaped%';
    return _queryTracks(
      where:
          "title LIKE ?1 ESCAPE '\\' OR artist LIKE ?1 ESCAPE '\\' "
          "OR album LIKE ?1 ESCAPE '\\' OR file_name LIKE ?1 ESCAPE '\\'",
      whereArgs: [pattern],
      orderBy: 'title COLLATE NOCASE',
    );
  }

  Future<Track?> trackById(int id) async =>
      (await _queryTracks(where: 'id = ?', whereArgs: [id])).firstOrNull;

  /// Loads tracks by id, in the order the ids are given. Ids that are no
  /// longer in the library are skipped.
  Future<List<Track>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _queryTracks(
      where: 'id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids,
    );
    final byId = {for (final track in rows) track.id: track};
    return [for (final id in ids) ?byId[id]];
  }

  /// Stores a length the player measured for a file whose tags had none.
  Future<void> setDuration(int trackId, Duration duration) async {
    await _db.update(
      'tracks',
      {'duration_ms': duration.inMilliseconds},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _changes.add(null);
  }

  Future<List<Track>> favorites() =>
      _queryTracks(where: 'is_favorite = 1', orderBy: 'title COLLATE NOCASE');

  Future<List<Track>> recentlyPlayed({int limit = 20}) => _queryTracks(
    where: 'last_played_at IS NOT NULL',
    orderBy: 'last_played_at DESC',
    limit: limit,
  );

  /// The tracks played most often, most played first.
  Future<List<Track>> mostPlayed({int limit = 20}) => _queryTracks(
    where: 'play_count > 0',
    orderBy: 'play_count DESC, last_played_at DESC',
    limit: limit,
  );

  Future<List<Track>> recentlyAdded({int limit = 20}) =>
      _queryTracks(orderBy: 'date_added DESC, id DESC', limit: limit);

  Future<void> setFavorite(int trackId, {required bool favorite}) async {
    await _db.update(
      'tracks',
      {'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    _changes.add(null);
  }

  /// Bumps the play count and stamps the track as just played.
  Future<void> recordPlay(int trackId, {DateTime? at}) async {
    await _db.rawUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played_at = ? '
      'WHERE id = ?',
      [(at ?? DateTime.now()).millisecondsSinceEpoch, trackId],
    );
    _changes.add(null);
  }

  Future<LibraryStats> stats() async {
    final row = (await _db.rawQuery(
      'SELECT COUNT(*) AS tracks, COUNT(DISTINCT album) AS albums, '
      'COUNT(DISTINCT artist) AS artists, '
      'COALESCE(SUM(duration_ms), 0) AS duration_ms, '
      'COALESCE(SUM(play_count), 0) AS plays FROM tracks',
    )).single;
    return LibraryStats(
      trackCount: row['tracks']! as int,
      albumCount: row['albums']! as int,
      artistCount: row['artists']! as int,
      totalDuration: Duration(milliseconds: row['duration_ms']! as int),
      playCount: row['plays']! as int,
    );
  }

  // ---- Albums, artists, genres and folders ----

  /// Every album, artist, genre or folder that has at least one track.
  Future<List<TrackGroupSummary>> groups(TrackGroup group) async {
    final column = group._column;
    final rows = await _db.rawQuery(
      'SELECT $column AS name, COUNT(*) AS track_count, '
      'MAX(art_path) AS art_path, '
      'MIN(COALESCE(album_artist, artist)) AS artist '
      'FROM tracks WHERE $column IS NOT NULL '
      'GROUP BY $column ORDER BY $column COLLATE NOCASE',
    );
    return rows.map(TrackGroupSummary.fromRow).toList();
  }

  /// The tracks of one album, artist, genre or folder.
  Future<List<Track>> groupTracks(TrackGroup group, String name) =>
      _queryTracks(
        where: '${group._column} = ?',
        whereArgs: [name],
        orderBy: group._trackOrder,
      );

  /// Sets of tracks that look like the same recording stored more than once:
  /// same title and artist, and a length within a second. Nothing is deleted;
  /// this only reports them.
  Future<List<List<Track>>> duplicates() async {
    final rows = await _queryTracks(
      where:
          'EXISTS (SELECT 1 FROM tracks other WHERE other.id != tracks.id '
          'AND other.title = tracks.title COLLATE NOCASE '
          "AND COALESCE(other.artist, '') = COALESCE(tracks.artist, '') "
          'COLLATE NOCASE '
          'AND ABS(other.duration_ms - tracks.duration_ms) < 1000)',
      orderBy: 'title COLLATE NOCASE, artist COLLATE NOCASE, duration_ms',
    );
    final sets = <List<Track>>[];
    for (final track in rows) {
      final last = sets.lastOrNull?.first;
      if (last != null &&
          last.title.toLowerCase() == track.title.toLowerCase() &&
          (last.artist ?? '').toLowerCase() ==
              (track.artist ?? '').toLowerCase() &&
          (last.duration - track.duration).abs() < const Duration(seconds: 1)) {
        sets.last.add(track);
      } else {
        sets.add([track]);
      }
    }
    return sets;
  }

  // ---- Imported lyrics ----

  /// Lyrics the user imported for a track, or null if there are none.
  Future<String?> importedLyrics(int trackId) async {
    final rows = await _db.query(
      'lyrics',
      columns: ['content'],
      where: 'track_id = ?',
      whereArgs: [trackId],
    );
    return rows.firstOrNull?['content'] as String?;
  }

  Future<void> setImportedLyrics(int trackId, String content) async {
    await _db.insert('lyrics', {
      'track_id': trackId,
      'content': content,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(null);
  }

  Future<void> removeImportedLyrics(int trackId) async {
    await _db.delete('lyrics', where: 'track_id = ?', whereArgs: [trackId]);
    _changes.add(null);
  }

  // ---- Playlists ----

  Future<List<Playlist>> playlists() async {
    final rows = await _db.rawQuery(
      'SELECT p.id, p.name, p.created_at, COUNT(pt.track_id) AS track_count '
      'FROM playlists p LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id '
      'GROUP BY p.id ORDER BY p.name COLLATE NOCASE',
    );
    return rows.map(Playlist.fromRow).toList();
  }

  Future<int> createPlaylist(String name) async {
    final id = await _db.insert('playlists', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _changes.add(null);
    return id;
  }

  Future<void> renamePlaylist(int playlistId, String name) async {
    await _db.update(
      'playlists',
      {'name': name},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
    _changes.add(null);
  }

  Future<void> deletePlaylist(int playlistId) async {
    await _db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    _changes.add(null);
  }

  /// Appends a track to a playlist. Adding a track twice is a no-op.
  Future<void> addToPlaylist(int playlistId, int trackId) async {
    await _db.rawInsert(
      'INSERT OR IGNORE INTO playlist_tracks(playlist_id, track_id, position) '
      'VALUES(?1, ?2, (SELECT COALESCE(MAX(position), -1) + 1 '
      'FROM playlist_tracks WHERE playlist_id = ?1))',
      [playlistId, trackId],
    );
    _changes.add(null);
  }

  Future<void> removeFromPlaylist(int playlistId, int trackId) async {
    await _db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
    _changes.add(null);
  }

  Future<List<Track>> playlistTracks(int playlistId) async {
    final rows = await _db.rawQuery(
      'SELECT t.* FROM tracks t '
      'JOIN playlist_tracks pt ON pt.track_id = t.id '
      'WHERE pt.playlist_id = ? ORDER BY pt.position',
      [playlistId],
    );
    return rows.map(Track.fromRow).toList();
  }

  // ---- Internals ----

  String _order(TrackSort sort, bool ascending) => ascending
      ? sort._orderBy
      : sort._orderBy.split(', ').map((column) => '$column DESC').join(', ');

  Future<List<Track>> _queryTracks({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final rows = await _db.query(
      'tracks',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    return rows.map(Track.fromRow).toList();
  }
}
