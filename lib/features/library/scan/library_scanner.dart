import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/library_repository.dart';
import 'discovered_file.dart';
import 'track_reader.dart';

/// Shrinks the image at [source] into [target]. Returns false if it couldn't,
/// in which case the original is kept.
typedef ArtworkShrinker = Future<bool> Function(String source, String target);

@immutable
class ScanProgress {
  const ScanProgress(this.processed, this.total);

  final int processed;
  final int total;
}

/// What a finished scan changed in the library.
@immutable
class ScanSummary {
  const ScanSummary({
    required this.scanned,
    required this.removed,
    required this.total,
    required this.cancelled,
  });

  /// New or changed files whose tags were read.
  final int scanned;

  /// Library entries dropped because their file is gone.
  final int removed;

  /// Audio files found on the device.
  final int total;
  final bool cancelled;
}

/// Brings the library database in line with the audio files on the device.
///
/// Only new or modified files are read, so a rescan of an unchanged library
/// is quick; a track is also read again if its cached cover has been cleared.
/// Files are never written to or deleted.
class LibraryScanner {
  LibraryScanner({
    required this.repository,
    required this.sources,
    required this.artworkDir,
    this.shrinkArtwork,
  });

  final LibraryRepository repository;
  final List<LibrarySource> sources;
  final String artworkDir;
  final ArtworkShrinker? shrinkArtwork;

  static const _batchSize = 20;

  bool _cancelled = false;

  /// Stops the running scan after the batch in progress. Tracks already
  /// stored stay in the library.
  void cancel() => _cancelled = true;

  Future<ScanSummary> scan({
    void Function(ScanProgress progress)? onProgress,
  }) async {
    _cancelled = false;

    final discovered = <String, DiscoveredFile>{};
    for (final source in sources) {
      for (final file in await source.discover()) {
        discovered[file.path] = file;
      }
    }

    final known = await repository.fingerprints();
    // Covers are kept in the cache folder, which the system or a cleaner app
    // may empty at any time. A track whose cover file has gone is read
    // again, which brings the cover back.
    final lostCover = {
      for (final MapEntry(key: uri, value: path)
          in (await repository.artworkPaths()).entries)
        if (!File(path).existsSync()) uri,
    };
    final changed = [
      for (final file in discovered.values)
        if (lostCover.contains(file.path) ||
            known[file.path] !=
                (
                  modifiedMs: file.modifiedMs,
                  sizeBytes: file.sizeBytes,
                  readerVersion: kTrackReaderVersion,
                ))
          file,
    ];

    var processed = 0;
    onProgress?.call(ScanProgress(0, changed.length));
    // Local copy: the isolate closure must not capture this scanner.
    final artworkDir = this.artworkDir;
    while (processed < changed.length && !_cancelled) {
      final batch = changed.sublist(
        processed,
        min(processed + _batchSize, changed.length),
      );
      final tracks = await Isolate.run(() => readTracks(batch, artworkDir));
      await _settleArtwork();
      await repository.upsertTracks(tracks, readerVersion: kTrackReaderVersion);
      processed += batch.length;
      onProgress?.call(ScanProgress(processed, changed.length));
    }

    // A cancelled scan hasn't seen everything, so it must not prune.
    final removed = _cancelled
        ? const <String>[]
        : [
            for (final uri in known.keys)
              if (!discovered.containsKey(uri)) uri,
          ];
    if (removed.isNotEmpty) await repository.removeTracks(removed);

    return ScanSummary(
      scanned: processed,
      removed: removed.length,
      total: discovered.length,
      cancelled: _cancelled,
    );
  }

  /// Moves covers the reader parked as too large into the cache, shrunk when
  /// the platform can do it and unchanged otherwise.
  Future<void> _settleArtwork() async {
    final pending = Directory(artworkDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(kPendingArtworkSuffix));
    for (final source in pending) {
      final target = source.path.substring(
        0,
        source.path.length - kPendingArtworkSuffix.length,
      );
      if (await shrinkArtwork?.call(source.path, target) ?? false) {
        source.deleteSync();
      } else {
        source.renameSync(target);
      }
    }
  }
}
