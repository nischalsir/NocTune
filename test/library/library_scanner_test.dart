import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/data/db/app_database.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/scan/discovered_file.dart';
import 'package:noctune/features/library/scan/library_scanner.dart';
import 'package:noctune/features/library/scan/library_sources.dart';
import 'package:noctune/features/library/scan/track_reader.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A valid 8-bit mono PCM WAV file of silence.
Uint8List _wav({int sampleRate = 8000, int seconds = 1}) {
  final dataLength = sampleRate * seconds;
  final bytes = BytesBuilder();
  void text(String value) => bytes.add(value.codeUnits);
  void u32(int value) => bytes.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u16(int value) => bytes.add(
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
  );
  text('RIFF');
  u32(36 + dataLength);
  text('WAVE');
  text('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate); // byte rate
  u16(1); // block align
  u16(8); // bits per sample
  text('data');
  u32(dataLength);
  bytes.add(Uint8List(dataLength)..fillRange(0, dataLength, 128));
  return bytes.toBytes();
}

class _FixedSource implements LibrarySource {
  _FixedSource(this.files);

  List<DiscoveredFile> files;

  @override
  Future<List<DiscoveredFile>> discover() async => files;
}

void main() {
  late Directory temp;
  late Directory music;
  late String artworkDir;
  late Database db;
  late LibraryRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('noctune_scan');
    music = Directory(p.join(temp.path, 'music'))..createSync();
    artworkDir = p.join(temp.path, 'artwork');
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) => File(p.join(music.path, name))
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  LibraryScanner scanner({
    List<LibrarySource>? sources,
    ArtworkShrinker? shrinkArtwork,
  }) => LibraryScanner(
    repository: repository,
    sources: sources ?? [DirectorySource(music)],
    artworkDir: artworkDir,
    shrinkArtwork: shrinkArtwork,
  );

  group('reading files', () {
    test('reads duration and sample rate from a real WAV file', () async {
      write('Silence.wav', _wav(sampleRate: 8000, seconds: 2));

      await scanner().scan();

      final track = (await repository.tracks()).single;
      expect(track.title, 'Silence');
      // Confirmed as uncompressed PCM from the header, not from the name.
      expect(track.codec, 'pcm');
      expect(track.sampleRate, 8000);
      expect(track.duration.inSeconds, 2);
      expect(track.folder, music.path);
      expect(track.sizeBytes, 16044);
    });

    test('keeps a corrupt file in the library under its file name', () async {
      write('Broken.flac', List.filled(256, 0x42));

      final summary = await scanner().scan();

      expect(summary.scanned, 1);
      final track = (await repository.tracks()).single;
      expect(track.title, 'Broken');
      // Its contents are not FLAC, so it is not recorded as FLAC.
      expect(track.codec, isNull);
      expect(track.duration, Duration.zero);
      expect(track.artPath, isNull);
    });

    test('falls back to what the platform index knows', () {
      final file = write('raw.opus', List.filled(64, 0));

      final track = readTrack(
        DiscoveredFile(
          path: file.path,
          sizeBytes: 64,
          modifiedMs: 1000,
          addedMs: 500,
          title: 'Indexed title',
          artist: 'Indexed artist',
          duration: const Duration(seconds: 90),
          year: 2019,
        ),
        artworkDir,
      );

      expect(track.title, 'Indexed title');
      expect(track.artist, 'Indexed artist');
      expect(track.duration, const Duration(seconds: 90));
      expect(track.year, 2019);
      expect(track.dateAdded.millisecondsSinceEpoch, 500);
    });

    test('finds audio in subfolders and ignores other files', () async {
      write('a.wav', _wav());
      write('Album/b.WAV', _wav());
      write('cover.jpg', [1, 2, 3]);
      write('notes.txt', [1, 2, 3]);

      final summary = await scanner().scan();

      expect(summary.total, 2);
      expect(await repository.tracks(), hasLength(2));
    });
  });

  group('rescanning', () {
    test('skips files that have not changed', () async {
      write('a.wav', _wav());
      await scanner().scan();

      final summary = await scanner().scan();

      expect(summary.scanned, 0);
      expect(summary.total, 1);
    });

    test('re-reads known files after the reader is improved', () async {
      write('a.wav', _wav());
      await scanner().scan();
      // As left behind by an older version of the app.
      await db.update('tracks', {'reader_version': 1, 'codec': 'wav'});

      final summary = await scanner().scan();

      expect(summary.scanned, 1);
      expect((await repository.tracks()).single.codec, 'pcm');
    });

    test('re-reads a file that was modified', () async {
      final file = write('a.wav', _wav(seconds: 1));
      await scanner().scan();

      file.writeAsBytesSync(_wav(seconds: 3));
      final summary = await scanner().scan();

      expect(summary.scanned, 1);
      expect((await repository.tracks()).single.duration.inSeconds, 3);
    });

    test('forgets tracks whose file is gone, keeping the rest', () async {
      write('keep.wav', _wav());
      final gone = write('gone.wav', _wav());
      await scanner().scan();

      gone.deleteSync();
      final summary = await scanner().scan();

      expect(summary.removed, 1);
      expect((await repository.tracks()).single.title, 'keep');
    });

    test('reports progress up to the number of changed files', () async {
      for (var i = 0; i < 45; i++) {
        write('track$i.wav', _wav(sampleRate: 100));
      }
      final progress = <ScanProgress>[];

      await scanner().scan(onProgress: progress.add);

      expect(progress.first.processed, 0);
      expect(progress.map((p) => p.processed), [0, 20, 40, 45]);
      expect(progress.every((p) => p.total == 45), isTrue);
    });

    test('a cancelled scan keeps what it read and removes nothing', () async {
      write('old.wav', _wav());
      await scanner().scan();
      final missing = (await repository.tracks()).single.uri;
      File(missing).deleteSync();
      for (var i = 0; i < 45; i++) {
        write('track$i.wav', _wav(sampleRate: 100));
      }

      final scan = scanner();
      final summary = await scan.scan(onProgress: (_) => scan.cancel());

      expect(summary.cancelled, isTrue);
      expect(summary.removed, 0);
      expect(summary.scanned, lessThan(45));
      expect((await repository.tracks()).map((t) => t.uri), contains(missing));
    });

    test('merges files from several sources', () async {
      final a = write('a.wav', _wav());
      final indexed = _FixedSource([
        DiscoveredFile(
          path: a.path,
          sizeBytes: a.lengthSync(),
          modifiedMs: 1,
          title: 'From index',
        ),
        const DiscoveredFile(
          path: '/storage/missing.flac',
          sizeBytes: 10,
          modifiedMs: 1,
          title: 'Elsewhere',
        ),
      ]);

      final summary = await scanner(sources: [indexed, DirectorySource(music)])
          .scan();

      expect(summary.total, 2);
      expect(await repository.tracks(), hasLength(2));
    });
  });

  group('artwork cache', () {
    File parkCover() =>
        File(p.join(artworkDir, 'abc.jpg$kPendingArtworkSuffix'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(1000, 9));

    test('uses the shrunk cover when the platform provides one', () async {
      write('a.wav', _wav());
      parkCover();

      await scanner(
        shrinkArtwork: (source, target) async {
          File(target).writeAsBytesSync([1, 2, 3]);
          return true;
        },
      ).scan();

      expect(File(p.join(artworkDir, 'abc.jpg')).lengthSync(), 3);
      expect(Directory(artworkDir).listSync(), hasLength(1));
    });

    test('keeps the original cover when it cannot be shrunk', () async {
      write('a.wav', _wav());
      parkCover();

      await scanner(shrinkArtwork: (_, _) async => false).scan();

      expect(File(p.join(artworkDir, 'abc.jpg')).lengthSync(), 1000);
      expect(Directory(artworkDir).listSync(), hasLength(1));
    });
  });
}
