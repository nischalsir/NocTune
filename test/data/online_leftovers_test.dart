import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/online_leftovers.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track _track(String uri) => Track(
  id: 0,
  uri: uri,
  fileName: p.basename(uri),
  folder: p.dirname(uri),
  title: p.basenameWithoutExtension(uri),
  duration: const Duration(minutes: 3),
  dateAdded: DateTime(2026),
  dateModified: DateTime(2026),
);

File _touch(String path) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync('x');

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late String musicDir;
  late String artworkDir;
  late Database db;
  late LibraryRepository repository;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('noctune_leftovers');
    musicDir = p.join(root.path, 'music');
    artworkDir = p.join(root.path, 'artwork');
    db = await AppDatabase.open(
      // A file per test: the in-memory database is shared between opens.
      path: p.join(root.path, 'library.db'),
      factory: databaseFactoryFfi,
    );
    repository = LibraryRepository(db);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('removes downloaded songs, their covers and settings, once', () async {
    final kept = _touch(p.join(musicDir, 'Imported', 'mine.flac'));
    final downloads = [
      _touch(p.join(musicDir, 'Jamendo', 'jamendo-1.mp3')),
      _touch(p.join(musicDir, 'Audius', 'audius-a.flac')),
      _touch(p.join(musicDir, 'Internet Archive', 'Show [s1]', '01.mp3')),
    ];
    final keptCover = _touch(p.join(artworkDir, 'abc123.jpg'));
    final onlineCover = _touch(p.join(artworkDir, 'audius-a.jpg'));
    await repository.upsertTracks([
      _track(kept.path),
      for (final file in downloads) _track(file.path),
    ]);
    SharedPreferences.setMockInitialValues({
      'online_search_enabled': false,
      'online_search_cache_v2': '{}',
      'search_history': ['keep me'],
    });
    final preferences = await SharedPreferences.getInstance();

    await removeOnlineLeftovers(
      preferences: preferences,
      repository: repository,
      musicDir: musicDir,
      artworkDir: artworkDir,
    );

    expect((await repository.fingerprints()).keys, [kept.path]);
    expect(kept.existsSync(), isTrue);
    for (final name in kOnlineDownloadFolders) {
      expect(Directory(p.join(musicDir, name)).existsSync(), isFalse);
    }
    expect(keptCover.existsSync(), isTrue);
    expect(onlineCover.existsSync(), isFalse);
    expect(preferences.containsKey('online_search_enabled'), isFalse);
    expect(preferences.containsKey('online_search_cache_v2'), isFalse);
    expect(preferences.getStringList('search_history'), ['keep me']);

    // A later launch leaves a folder of that name alone.
    final later = _touch(p.join(musicDir, 'Audius', 'mine.mp3'));
    await removeOnlineLeftovers(
      preferences: preferences,
      repository: repository,
      musicDir: musicDir,
      artworkDir: artworkDir,
    );
    expect(later.existsSync(), isTrue);
  });

  test('does nothing harmful when nothing was downloaded', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await removeOnlineLeftovers(
      preferences: preferences,
      repository: repository,
      musicDir: musicDir,
      artworkDir: artworkDir,
    );

    expect(await repository.fingerprints(), isEmpty);
  });
}
