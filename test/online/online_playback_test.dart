import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctune/app/providers.dart';
import 'package:noctune/data/models/track.dart';
import 'package:noctune/data/repositories/library_repository.dart';
import 'package:noctune/features/library/scan/scan_controller.dart';
import 'package:noctune/features/online/online_source.dart';
import 'package:noctune/features/online/online_playback.dart';
import 'package:noctune/features/playback/playback_mapping.dart';
import 'package:path/path.dart' as p;

class _Library extends Fake implements LibraryRepository {
  final byUri = <String, Track>{};

  @override
  Future<Track?> trackByUri(String uri) async => byUri[uri];
}

class _QuietScan extends ScanController {
  int refreshes = 0;

  @override
  ScanState build() => const ScanIdle();

  @override
  Future<void> refreshIfPermitted() async => refreshes++;
}

OnlineTrack _online(String id, {bool downloadable = true}) => OnlineTrack(
  id: id,
  title: 'Song $id',
  artist: 'Lena Orsa',
  streamUrl: Uri.parse('https://prod-1.storage.jamendo.com/?trackid=$id'),
  imageUrl: Uri.parse('https://usercontent.jamendo.com/?id=$id'),
  downloadUrl: downloadable
      ? Uri.parse('https://prod-1.storage.jamendo.com/download/$id')
      : null,
  duration: const Duration(minutes: 3),
);

OnlineTrack _audius(String id) => OnlineTrack(
  source: OnlineSourceId.audius,
  id: id,
  title: 'Beat $id',
  streamUrl: Uri.parse('https://api.audius.co/v1/tracks/$id/stream'),
  downloadUrl: Uri.parse('https://api.audius.co/v1/tracks/$id/download'),
);

OnlineTrack _archive(String file, {String album = 'Live at Ashkenaz'}) =>
    OnlineTrack(
      source: OnlineSourceId.archive,
      id: 'samh2024/$file',
      title: file,
      album: album,
      streamUrl: Uri.parse('https://archive.org/download/samh2024/$file'),
      downloadUrl: Uri.parse('https://archive.org/download/samh2024/$file'),
      imageUrl: Uri.parse('https://archive.org/services/img/samh2024'),
    );

void main() {
  late Directory root;
  late AppPaths paths;
  late _Library library;
  late List<(List<Track>, int)> played;
  late List<Uri> fetched;
  late bool fetchFails;

  /// Downloads whose address contains one of these fail.
  late Set<String> failing;

  /// What a download's file starts with.
  late List<int> head;

  Future<void> fakeFetch(Uri url, File target) async {
    fetched.add(url);
    if (fetchFails || failing.any('$url'.contains)) {
      throw const SocketException('offline');
    }
    await target.writeAsBytes([...head, ...'data from $url'.codeUnits]);
  }

  OnlinePlayer player() => OnlinePlayer(
    paths: paths,
    repository: library,
    fetchFile: fakeFetch,
    playTracks: (tracks, index) async => played.add((tracks, index)),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('noctune_online');
    paths = (
      artworkDir: p.join(root.path, 'artwork'),
      musicDir: p.join(root.path, 'music'),
      coverDir: p.join(root.path, 'covers'),
    );
    library = _Library();
    played = [];
    fetched = [];
    fetchFails = false;
    failing = {};
    head = 'ID3'.codeUnits;
  });
  tearDown(() => root.deleteSync(recursive: true));

  void download(OnlineTrack track) {
    downloadedFile(paths, track)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('mp3');
  }

  test('online, a result streams with its cover saved first', () async {
    final results = [_online('1'), _online('2')];

    final outcome = await player().play(results, 1);

    expect(outcome, OnlinePlayOutcome.started);
    final (tracks, index) = played.single;
    expect(index, 1);
    expect(tracks[1].isStreamed, isTrue);
    expect('${tracks[1].playbackUri}', '${results[1].streamUrl}');
    expect(tracks[1].artPath, coverFile(paths, results[1]).path);
    expect(File(tracks[1].artPath!).existsSync(), isTrue);
    // Not in the library, so the listening history leaves it alone.
    expect(
      mediaItemFromTrack(tracks[1]).extras,
      isNot(contains(kTrackIdExtra)),
    );
  });

  test('a cover that fails to load does not stop playback', () async {
    fetchFails = true;

    await player().play([_online('1')], 0);

    expect(played.single.$1.single.artPath, isNull);
  });

  test('a downloaded result plays from the library copy', () async {
    final result = _online('1');
    download(result);
    final path = downloadedFile(paths, result).path;
    library.byUri[path] = Track(
      id: 42,
      uri: path,
      fileName: 'jamendo-1.mp3',
      folder: p.dirname(path),
      title: 'Song 1',
      dateAdded: DateTime(2026),
      dateModified: DateTime(2026),
    );

    await player().play([result], 0);

    final track = played.single.$1.single;
    expect(track.id, 42);
    expect(track.isStreamed, isFalse);
  });

  test('offline, a downloaded result plays from its file', () async {
    final results = [_online('1'), _online('2')];
    download(results[1]);

    final outcome = await player().play(
      results,
      1,
      offline: {OnlineSourceId.jamendo},
    );

    expect(outcome, OnlinePlayOutcome.started);
    final (tracks, index) = played.single;
    // Only what can play without a connection is queued.
    expect(tracks, hasLength(1));
    expect(index, 0);
    expect(
      tracks.single.playbackUri,
      Uri.file(downloadedFile(paths, results[1]).path),
    );
    expect(fetched, isEmpty);
  });

  test('offline, a result that is not downloaded is not started', () async {
    final outcome = await player().play(
      [_online('1')],
      0,
      offline: {OnlineSourceId.jamendo},
    );

    expect(outcome, OnlinePlayOutcome.needsConnection);
    expect(played, isEmpty);
  });

  String inMusic(File file) => p.relative(file.path, from: paths.musicDir);

  test('Jamendo paths are unchanged', () {
    expect(
      inMusic(downloadedFile(paths, _online('7'))),
      p.join('Jamendo', 'jamendo-7.mp3'),
    );
    expect(p.basename(coverFile(paths, _online('7')).path), 'jamendo-7.jpg');
  });

  test('an Archive track goes in a folder named after its item', () {
    final track = _archive('set 1/01 Iko.mp3', album: 'Live: 1977/05/08?');

    expect(
      inMusic(downloadedFile(paths, track)),
      p.join(
        'Internet Archive',
        'Live_ 1977_05_08_ [samh2024]',
        'set 1_01 Iko.mp3',
      ),
    );
    expect(p.basename(coverFile(paths, track).path), 'archive-samh2024.jpg');
    expect(streamedTrack(track).folder, 'Internet Archive');
  });

  test('a name that cleans to nothing uses the identifier', () {
    expect(
      inMusic(downloadedFile(paths, _archive('a.mp3', album: ' ... '))),
      p.join('Internet Archive', 'samh2024', 'a.mp3'),
    );
  });

  test('two items with the same title get their own folders', () {
    final other = OnlineTrack(
      source: OnlineSourceId.archive,
      id: 'gd77b/a.mp3',
      title: 'a',
      album: 'Live at Ashkenaz',
      streamUrl: Uri.parse('https://archive.org/download/gd77b/a.mp3'),
    );

    expect(
      downloadedFile(paths, _archive('a.mp3')).path,
      isNot(downloadedFile(paths, other).path),
    );
  });

  test('a very long title is cut short', () {
    final folder = p.basename(
      downloadedFile(paths, _archive('a.mp3', album: 'ॐ' * 300)).parent.path,
    );

    expect(folder, endsWith(' [samh2024]'));
    expect(folder.length, lessThanOrEqualTo(100 + ' [samh2024]'.length));
  });

  test('Audius files and covers are named by id', () {
    expect(
      inMusic(downloadedFile(paths, _audius('KlK59'))),
      p.join('Audius', 'audius-KlK59.mp3'),
    );
    expect(
      p.basename(coverFile(paths, _audius('KlK59')).path),
      'audius-KlK59.jpg',
    );
    expect(streamedTrack(_audius('KlK59')).folder, 'Audius');
  });

  test('the file type is read from its first bytes', () {
    expect(audioExtension('fLaC'.codeUnits), 'flac');
    expect(audioExtension('RIFF'.codeUnits), 'wav');
    expect(audioExtension('OggS'.codeUnits), 'ogg');
    expect(audioExtension([0, 0, 0, 32, ...'ftypM4A '.codeUnits]), 'm4a');
    expect(audioExtension('ID3'.codeUnits), 'mp3');
    expect(audioExtension(const []), 'mp3');
  });

  test('only the offline source is held to its downloads', () async {
    final results = [_online('1'), _audius('a')];

    final outcome = await player().play(
      results,
      0,
      offline: {OnlineSourceId.audius},
    );

    expect(outcome, OnlinePlayOutcome.started);
    expect(played.single.$1.map((track) => track.title), ['Song 1']);
  });

  group('downloads', () {
    late ProviderContainer container;
    late _QuietScan scan;

    setUp(() {
      scan = _QuietScan();
      container = ProviderContainer(
        overrides: [
          appPathsProvider.overrideWithValue(paths),
          fileFetcherProvider.overrideWithValue(fakeFetch),
          scanControllerProvider.overrideWith(() => scan),
        ],
      );
      addTearDown(container.dispose);
    });

    test('a download is saved in the music folder and scanned in', () async {
      final track = _online('7');

      final saved = await container
          .read(onlineDownloadsProvider.notifier)
          .download(track);

      expect(saved, isTrue);
      expect(downloadedFile(paths, track).existsSync(), isTrue);
      expect(scan.refreshes, 1);
      expect(container.read(onlineDownloadsProvider), isEmpty);
    });

    test('a failed download leaves nothing behind and says so', () async {
      fetchFails = true;
      final track = _online('7');

      final saved = await container
          .read(onlineDownloadsProvider.notifier)
          .download(track);

      expect(saved, isFalse);
      final file = downloadedFile(paths, track);
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.part').existsSync(), isFalse);
      expect(
        container.read(onlineDownloadsProvider)['jamendo:7'],
        DownloadStatus.failed,
      );
    });

    test('an Audius FLAC is saved as .flac and counts as downloaded', () async {
      head = 'fLaC'.codeUnits;

      final saved = await container
          .read(onlineDownloadsProvider.notifier)
          .download(_audius('x'));

      expect(saved, isTrue);
      final flac = File(p.join(paths.musicDir, 'Audius', 'audius-x.flac'));
      expect(flac.existsSync(), isTrue);
      expect(downloadedFile(paths, _audius('x')).path, flac.path);
      expect(player().isDownloaded(_audius('x')), isTrue);
    });

    test('an unsynchronised ID3 tag is undone, so its title is read', () async {
      // An ID3v2.3 tag as the Internet Archive writes it: a UTF-16 title
      // whose byte-order mark (FF FE) is stuffed with a 00 after the FF.
      final title = [
        0xFF,
        0xFE,
        for (final unit in 'Mexicali Blues'.codeUnits) ...[unit, 0],
      ];
      final frame = [
        ...'TIT2'.codeUnits,
        0,
        0,
        0,
        1 + title.length,
        0,
        0,
        1,
        ...title,
      ];
      final stuffed = [
        for (final byte in frame) ...(byte == 0xFF ? [0xFF, 0] : [byte]),
      ];
      final audio = [0xFF, 0xFB, 0x90, 0x64, ...List.filled(400, 0)];
      head = [
        ...'ID3'.codeUnits,
        3,
        0,
        0x80,
        0,
        0,
        0,
        stuffed.length,
        ...stuffed,
        ...audio,
      ];
      final track = _archive('03MexicaliBlues.mp3');

      await container.read(onlineDownloadsProvider.notifier).download(track);

      final file = downloadedFile(paths, track);
      final bytes = file.readAsBytesSync();
      expect(bytes[5] & 0x80, 0, reason: 'the flag is cleared');
      expect(bytes.sublist(10, 10 + frame.length), frame);
      expect(readMetadata(file).title, 'Mexicali Blues');
    });

    test('a tag that is not unsynchronised is left alone', () async {
      head = [...'ID3'.codeUnits, 3, 0, 0, 0, 0, 0, 4, 1, 2, 0xFF, 0];
      final track = _archive('plain.mp3');

      await container.read(onlineDownloadsProvider.notifier).download(track);

      expect(
        downloadedFile(paths, track).readAsBytesSync().sublist(0, head.length),
        head,
      );
    });

    test('downloads are keyed by source', () async {
      fetchFails = true;
      final downloads = container.read(onlineDownloadsProvider.notifier);

      await downloads.download(_online('x'));

      expect(container.read(onlineDownloadsProvider), {
        'jamendo:x': DownloadStatus.failed,
      });
      expect(container.read(onlineDownloadsProvider)[_audius('x').key], isNull);
    });

    test(
      'download all goes in order, carries on after a failure, scans once',
      () async {
        final tracks = [
          _archive('a.mp3'),
          _archive('b.mp3'),
          _archive('c.mp3'),
        ];
        failing = {'b.mp3'};

        final failed = await container
            .read(onlineDownloadsProvider.notifier)
            .downloadAll(tracks);

        expect(failed, 1);
        expect(fetched.map((url) => p.basename(url.path)), [
          'a.mp3',
          'b.mp3',
          'c.mp3',
        ]);
        expect(downloadedFile(paths, tracks[0]).existsSync(), isTrue);
        expect(downloadedFile(paths, tracks[1]).existsSync(), isFalse);
        expect(downloadedFile(paths, tracks[2]).existsSync(), isTrue);
        expect(scan.refreshes, 1);
        expect(container.read(onlineDownloadsProvider), {
          tracks[1].key: DownloadStatus.failed,
        });
      },
    );

    test('download all skips what is already downloaded', () async {
      final tracks = [_archive('a.mp3'), _archive('b.mp3')];
      download(tracks[0]);

      await container
          .read(onlineDownloadsProvider.notifier)
          .downloadAll(tracks);

      expect(fetched.map((url) => p.basename(url.path)), ['b.mp3']);
    });

    test('a track Jamendo does not allow to download is not fetched', () async {
      final saved = await container
          .read(onlineDownloadsProvider.notifier)
          .download(_online('7', downloadable: false));

      expect(saved, isFalse);
      expect(fetched, isEmpty);
    });
  });
}
