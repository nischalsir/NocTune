import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import 'discovered_file.dart';
import 'library_permission.dart';
import 'library_scanner.dart';
import 'library_sources.dart';

sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle([this.lastScan]);

  /// Result of the most recent scan in this session, if there was one.
  final ScanSummary? lastScan;
}

class ScanRunning extends ScanState {
  const ScanRunning(this.processed, this.total);

  final int processed;

  /// Files to read; 0 while the device is still being searched.
  final int total;
}

class ScanNeedsPermission extends ScanState {
  const ScanNeedsPermission({required this.permanentlyDenied});

  final bool permanentlyDenied;
}

class ScanFailed extends ScanState {
  const ScanFailed(this.message);

  final String message;
}

final libraryPermissionProvider = Provider<LibraryPermission>(
  (ref) => const LibraryPermission(),
);

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  final paths = ref.watch(appPathsProvider);
  return LibraryScanner(
    repository: ref.watch(libraryRepositoryProvider),
    sources: [
      if (Platform.isAndroid) const MediaStoreSource(),
      DirectorySource(Directory(paths.musicDir)),
    ],
    artworkDir: paths.artworkDir,
    shrinkArtwork: shrinkArtworkOnPlatform,
  );
});

/// Runs library scans and file imports, and reports their progress.
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  /// Scans the device, asking for storage access first if needed.
  Future<void> scan() async {
    if (state is ScanRunning) return;
    final access = await ref.read(libraryPermissionProvider).request();
    if (access != LibraryAccess.granted) {
      state = ScanNeedsPermission(
        permanentlyDenied: access == LibraryAccess.permanentlyDenied,
      );
      return;
    }
    await _run();
  }

  /// Picks up new and changed files at launch, but only if access was already
  /// granted: the app never opens with a permission prompt.
  Future<void> refreshIfPermitted() async {
    if (state is ScanRunning) return;
    final access = await ref.read(libraryPermissionProvider).check();
    if (access == LibraryAccess.granted) await _run();
  }

  void cancel() => ref.read(libraryScannerProvider).cancel();

  /// Lets the user pick audio files and copies them into the app's music
  /// folder. The originals are left where they are.
  Future<void> importFiles() async {
    if (state is ScanRunning) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAudioExtensions.toList(),
    );
    if (picked.isEmpty) return;

    final musicDir = Directory(ref.read(appPathsProvider).musicDir)
      ..createSync(recursive: true);
    try {
      for (final file in picked) {
        final source = file.path;
        if (source == null) continue;
        await File(source).copy(p.join(musicDir.path, file.name));
      }
    } on FileSystemException catch (error) {
      state = ScanFailed("Couldn't import: ${error.message}");
      return;
    }
    await FilePicker.clearTemporaryFiles();
    await _run();
  }

  Future<void> _run() async {
    state = const ScanRunning(0, 0);
    try {
      final summary = await ref
          .read(libraryScannerProvider)
          .scan(
            onProgress: (progress) =>
                state = ScanRunning(progress.processed, progress.total),
          );
      state = ScanIdle(summary);
    } on PlatformException catch (error) {
      state = error.code == 'permission_denied'
          ? const ScanNeedsPermission(permanentlyDenied: false)
          : ScanFailed(error.message ?? "The device's music couldn't be read.");
    } on FileSystemException catch (error) {
      state = ScanFailed("Scan stopped: ${error.message}");
    }
  }
}

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(
  ScanController.new,
);
