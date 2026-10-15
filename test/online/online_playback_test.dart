import 'dart:io';

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

void main() {
  late Directory root;
  late AppPaths paths;
  late _Library library;
  late List<(List<Track>, int)> played;
  late List<Uri> fetched;
  late bool fetchFails;

  Future<void> fakeFetch(Uri url, File target) async {
    fetched.add(url);
    if (fetchFails) throw const SocketException('offline');
    await target.writeAsString('data from $url');
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
  });
  tearDown(() => root.deleteSync(recursive: true));

  void download(OnlineTrack track) {
    downloadedFile(paths, track)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('mp3');
  }

  test('online, a result streams with its cover saved first', () async {
    final results = [_online('1'), _online('2')];

    final outcome = await player().play(results, 1, offline: false);

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

    await player().play([_online('1')], 0, offline: false);

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

    await player().play([result], 0, offline: false);

    final track = played.single.$1.single;
    expect(track.id, 42);
    expect(track.isStreamed, isFalse);
  });

  test('offline, a downloaded result plays from its file', () async {
    final results = [_online('1'), _online('2')];
    download(results[1]);

    final outcome = await player().play(results, 1, offline: true);

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
    final outcome = await player().play([_online('1')], 0, offline: true);

    expect(outcome, OnlinePlayOutcome.needsConnection);
    expect(played, isEmpty);
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
        container.read(onlineDownloadsProvider)['7'],
        DownloadStatus.failed,
      );
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
