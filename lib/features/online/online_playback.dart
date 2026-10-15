import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../library/scan/scan_controller.dart';
import 'online_source.dart';

/// Saves the file at [url] as [target]. Replaced with a fake in tests.
typedef FileFetcher = Future<void> Function(Uri url, File target);

Future<void> fetchFileOverHttps(Uri url, File target) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(url);
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Unexpected status ${response.statusCode}', uri: url);
    }
    await response.pipe(target.openWrite());
  } finally {
    client.close(force: true);
  }
}

final fileFetcherProvider = Provider<FileFetcher>((ref) => fetchFileOverHttps);

/// Where a downloaded Jamendo track is kept: in the app's music folder, which
/// every scan reads, so it joins the library like an imported file.
File downloadedFile(AppPaths paths, OnlineTrack track) =>
    File(p.join(paths.musicDir, 'Jamendo', 'jamendo-${track.id}.mp3'));

/// Its cover, kept with the library's covers so the player shows it like
/// any other.
File coverFile(AppPaths paths, OnlineTrack track) =>
    File(p.join(paths.artworkDir, 'jamendo-${track.id}.jpg'));

/// Describes a Jamendo track as one the player can stream.
Track streamedTrack(OnlineTrack track, {String? artPath}) => Track(
  uri: '${track.streamUrl}',
  fileName: 'jamendo-${track.id}.mp3',
  folder: 'Jamendo',
  title: track.title,
  artist: track.artist,
  album: track.album,
  duration: track.duration,
  codec: 'mp3',
  dateAdded: DateTime.fromMillisecondsSinceEpoch(0),
  dateModified: DateTime.fromMillisecondsSinceEpoch(0),
  artPath: artPath,
  artUrl: track.imageUrl,
);

/// What happened when an online result was tapped.
enum OnlinePlayOutcome {
  started,

  /// It isn't downloaded and there is no connection.
  needsConnection,
}

/// Plays Jamendo results: the downloaded copy when there is one, streamed
/// otherwise.
class OnlinePlayer {
  OnlinePlayer({
    required this.paths,
    required this.repository,
    required this.fetchFile,
    required this.playTracks,
  });

  final AppPaths paths;
  final LibraryRepository repository;
  final FileFetcher fetchFile;
  final Future<void> Function(List<Track> tracks, int initialIndex) playTracks;

  /// Longest wait for covers before playing; whatever has not arrived by
  /// then plays without one.
  static const coverWait = Duration(seconds: 3);

  bool isDownloaded(OnlineTrack track) =>
      downloadedFile(paths, track).existsSync();

  /// Plays [tracks] from [index]. [offline] when the search that found them
  /// could not reach Jamendo: only downloaded tracks are queued then, and
  /// one that isn't downloaded is not started.
  Future<OnlinePlayOutcome> play(
    List<OnlineTrack> tracks,
    int index, {
    required bool offline,
  }) async {
    final tapped = tracks[index];
    if (offline && !isDownloaded(tapped)) {
      return OnlinePlayOutcome.needsConnection;
    }
    final queued = [
      for (final track in tracks)
        if (!offline || isDownloaded(track)) track,
    ];
    if (!offline) await _fetchCovers(queued);
    final playable = [for (final track in queued) await _playable(track)];
    await playTracks(playable, queued.indexOf(tapped));
    return OnlinePlayOutcome.started;
  }

  /// The library's copy of a downloaded track, so it counts in the
  /// listening history; failing that the file itself; else the stream.
  Future<Track> _playable(OnlineTrack track) async {
    final file = downloadedFile(paths, track);
    if (file.existsSync()) {
      return await repository.trackByUri(file.path) ??
          streamedTrack(track).copyAsFile(file.path);
    }
    final cover = coverFile(paths, track);
    return streamedTrack(
      track,
      artPath: cover.existsSync() ? cover.path : null,
    );
  }

  Future<void> _fetchCovers(List<OnlineTrack> tracks) async {
    final pending = [
      for (final track in tracks)
        if (track.imageUrl != null && !coverFile(paths, track).existsSync())
          _fetchCover(track),
    ];
    if (pending.isEmpty) return;
    await Future.wait(pending).timeout(coverWait, onTimeout: () => const []);
  }

  Future<void> _fetchCover(OnlineTrack track) async {
    final target = coverFile(paths, track);
    final part = File('${target.path}.part');
    try {
      part.parent.createSync(recursive: true);
      await fetchFile(track.imageUrl!, part);
      part.renameSync(target.path);
    } on Exception {
      // No cover is fine; the player shows its placeholder.
      if (part.existsSync()) part.deleteSync();
    }
  }
}

extension on Track {
  Track copyAsFile(String path) => Track(
    uri: path,
    fileName: p.basename(path),
    folder: p.dirname(path),
    title: title,
    artist: artist,
    album: album,
    duration: duration,
    codec: codec,
    dateAdded: dateAdded,
    dateModified: dateModified,
  );
}

final onlinePlayerProvider = Provider<OnlinePlayer>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return OnlinePlayer(
    paths: ref.watch(appPathsProvider),
    repository: ref.watch(libraryRepositoryProvider),
    fetchFile: ref.watch(fileFetcherProvider),
    playTracks: (tracks, index) =>
        handler.playTracks(tracks, initialIndex: index),
  );
});

/// Downloads in progress or failed, by Jamendo id. A finished download is
/// a file on the device; see [OnlinePlayer.isDownloaded].
class OnlineDownloads extends Notifier<Map<String, DownloadStatus>> {
  @override
  Map<String, DownloadStatus> build() => const {};

  /// Saves [track] for offline listening and adds it to the library.
  /// Returns false if it couldn't be downloaded.
  Future<bool> download(OnlineTrack track) async {
    final url = track.downloadUrl;
    if (url == null || state[track.id] == DownloadStatus.downloading) {
      return false;
    }
    state = {...state, track.id: DownloadStatus.downloading};
    final target = downloadedFile(ref.read(appPathsProvider), track);
    final part = File('${target.path}.part');
    try {
      part.parent.createSync(recursive: true);
      await ref.read(fileFetcherProvider)(url, part);
      part.renameSync(target.path);
    } on Exception {
      if (part.existsSync()) part.deleteSync();
      state = {...state, track.id: DownloadStatus.failed};
      return false;
    }
    state = {...state}..remove(track.id);
    // The file is in the music folder; a scan reads its tags and cover.
    await ref.read(scanControllerProvider.notifier).refreshIfPermitted();
    return true;
  }
}

enum DownloadStatus { downloading, failed }

final onlineDownloadsProvider =
    NotifierProvider<OnlineDownloads, Map<String, DownloadStatus>>(
      OnlineDownloads.new,
    );
