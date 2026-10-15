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

/// Where a downloaded track is kept: in the app's music folder, which every
/// scan reads, so it joins the library like an imported file. Each source
/// has its own folder there; an Internet Archive item has its own inside
/// it. An Audius download keeps the type its artist uploaded, so it is
/// looked for under each.
File downloadedFile(AppPaths paths, OnlineTrack track) {
  final folder = p.join(paths.musicDir, _folders[track.source]);
  switch (track.source) {
    case OnlineSourceId.jamendo:
      return File(p.join(folder, 'jamendo-${track.id}.mp3'));
    case OnlineSourceId.audius:
      for (final extension in _audioExtensions) {
        final file = File(p.join(folder, 'audius-${track.id}.$extension'));
        if (file.existsSync()) return file;
      }
      return File(p.join(folder, 'audius-${track.id}.mp3'));
    case OnlineSourceId.archive:
      final (identifier, name) = _archiveParts(track);
      return File(
        p.join(
          folder,
          safeName(track.album ?? '', fallback: identifier),
          safeName(name, fallback: identifier),
        ),
      );
  }
}

/// Its cover, kept with the library's covers so the player shows it like
/// any other. An Internet Archive item's tracks share one.
File coverFile(AppPaths paths, OnlineTrack track) => File(
  p.join(paths.artworkDir, switch (track.source) {
    OnlineSourceId.archive => 'archive-${_archiveParts(track).$1}.jpg',
    final source => '${source.name}-${track.id}.jpg',
  }),
);

const _folders = {
  OnlineSourceId.jamendo: 'Jamendo',
  OnlineSourceId.audius: 'Audius',
  OnlineSourceId.archive: 'Internet Archive',
};

const _audioExtensions = ['flac', 'wav', 'ogg', 'm4a', 'mp3'];

/// An Internet Archive track's item and file name, from its id.
(String, String) _archiveParts(OnlineTrack track) {
  final slash = track.id.indexOf('/');
  return slash < 0
      ? (track.id, track.id)
      : (track.id.substring(0, slash), track.id.substring(slash + 1));
}

/// [name] made safe as one file or folder name on Android and Windows;
/// [fallback] when nothing is left of it.
String safeName(String name, {required String fallback}) {
  final cleaned = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  return cleaned.isEmpty ? fallback : cleaned;
}

/// The type of an audio file, from its first bytes.
String audioExtension(List<int> head) {
  bool startsWith(String magic, [int at = 0]) =>
      head.length >= at + magic.length &&
      String.fromCharCodes(head.sublist(at, at + magic.length)) == magic;
  if (startsWith('fLaC')) return 'flac';
  if (startsWith('RIFF')) return 'wav';
  if (startsWith('OggS')) return 'ogg';
  if (startsWith('ftyp', 4)) return 'm4a';
  return 'mp3';
}

/// Describes an online track as one the player can stream.
Track streamedTrack(OnlineTrack track, {String? artPath}) => Track(
  uri: '${track.streamUrl}',
  fileName: _defaultFile(track),
  folder: _folders[track.source]!,
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

/// The name [track] would be saved under before its type is known.
String _defaultFile(OnlineTrack track) => switch (track.source) {
  OnlineSourceId.archive => safeName(
    _archiveParts(track).$2,
    fallback: _archiveParts(track).$1,
  ),
  final source => '${source.name}-${track.id}.mp3',
};

/// What happened when an online result was tapped.
enum OnlinePlayOutcome {
  started,

  /// It isn't downloaded and there is no connection.
  needsConnection,
}

/// Plays online results: the downloaded copy when there is one, streamed
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
  /// could not get online: only downloaded tracks are queued then, and one
  /// that isn't downloaded is not started.
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

/// Downloads in progress or failed, by [OnlineItem.key]. A finished
/// download is a file on the device; see [OnlinePlayer.isDownloaded].
class OnlineDownloads extends Notifier<Map<String, DownloadStatus>> {
  @override
  Map<String, DownloadStatus> build() => const {};

  /// Saves [track] for offline listening and, with [scan], adds it to the
  /// library. Returns false if it couldn't be downloaded.
  Future<bool> download(OnlineTrack track, {bool scan = true}) async {
    final url = track.downloadUrl;
    if (url == null || state[track.key] == DownloadStatus.downloading) {
      return false;
    }
    state = {...state, track.key: DownloadStatus.downloading};
    final paths = ref.read(appPathsProvider);
    final part = File('${downloadedFile(paths, track).path}.part');
    try {
      part.parent.createSync(recursive: true);
      await ref.read(fileFetcherProvider)(url, part);
      part.renameSync(_finalPath(part, track));
    } on Exception {
      if (part.existsSync()) part.deleteSync();
      state = {...state, track.key: DownloadStatus.failed};
      return false;
    }
    state = {...state}..remove(track.key);
    // The file is in the music folder; a scan reads its tags and cover.
    if (scan) {
      await ref.read(scanControllerProvider.notifier).refreshIfPermitted();
    }
    return true;
  }

  /// Downloads [tracks] one after another, skipping those already on the
  /// device or not allowed, carrying on past failures, and scanning once at
  /// the end. Returns how many failed.
  Future<int> downloadAll(List<OnlineTrack> tracks) async {
    final paths = ref.read(appPathsProvider);
    var failed = 0;
    var saved = 0;
    for (final track in tracks) {
      if (track.downloadUrl == null ||
          downloadedFile(paths, track).existsSync()) {
        continue;
      }
      if (await download(track, scan: false)) {
        saved++;
      } else {
        failed++;
      }
    }
    if (saved > 0) {
      await ref.read(scanControllerProvider.notifier).refreshIfPermitted();
    }
    return failed;
  }

  /// Audius hands over the file its artist uploaded, whatever name it
  /// suggests, so its type is read from the file itself.
  static String _finalPath(File part, OnlineTrack track) {
    final target = part.path.substring(0, part.path.length - '.part'.length);
    if (track.source != OnlineSourceId.audius) return target;
    final file = part.openSync();
    try {
      return '${p.withoutExtension(target)}.${audioExtension(file.readSync(12))}';
    } finally {
      file.closeSync();
    }
  }
}

enum DownloadStatus { downloading, failed }

final onlineDownloadsProvider =
    NotifierProvider<OnlineDownloads, Map<String, DownloadStatus>>(
      OnlineDownloads.new,
    );
