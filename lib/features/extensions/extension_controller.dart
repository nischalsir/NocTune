import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../library/scan/scan_controller.dart';
import 'extension_channel.dart';
import 'extension_models.dart';

final extensionChannelProvider = Provider<ExtensionChannel>(
  (ref) => const ExtensionChannel(),
);

@immutable
class ExtensionState {
  const ExtensionState({
    this.extensions = const [],
    this.loading = false,
    this.downloadingKeys = const {},
    this.downloadedPaths = const {},
    this.downloadQueue = const [],
  });

  final List<InstalledExtension> extensions;
  final bool loading;
  final Set<String> downloadingKeys;
  final Map<String, String> downloadedPaths;
  final List<ExtensionDownloadItem> downloadQueue;

  int get activeDownloadCount =>
      downloadQueue.where((item) => item.isActive).length;

  int get completedDownloadCount => downloadQueue
      .where((item) => item.status == ExtensionDownloadStatus.completed)
      .length;

  /// True when at least one enabled extension can search or download tracks.
  bool get hasActiveSearchOrDownload => extensions.any(
    (ext) =>
        ext.enabled &&
        (ext.hasMetadataProvider ||
            ext.hasCustomSearch ||
            ext.hasDownloadProvider ||
            ext.hasUrlHandler),
  );

  /// Enabled extensions that can be selected as a search source.
  List<InstalledExtension> get enabledSearchExtensions => [
    for (final ext in extensions)
      if (ext.enabled &&
          (ext.hasMetadataProvider ||
              ext.hasCustomSearch ||
              ext.hasDownloadProvider))
        ext,
  ];

  /// Enabled extensions that provide audio downloads.
  List<InstalledExtension> get enabledDownloadExtensions => [
    for (final ext in extensions)
      if (ext.enabled && ext.hasDownloadProvider) ext,
  ];

  /// True when at least one enabled extension provides downloads.
  bool get hasActiveDownloader =>
      extensions.any((ext) => ext.enabled && ext.hasDownloadProvider);

  /// True when at least one enabled extension provides lyrics.
  bool get hasActiveLyrics =>
      extensions.any((ext) => ext.enabled && ext.hasLyricsProvider);

  String get summary {
    if (extensions.isEmpty) {
      return 'Load .spotiflac-ext, .sflx or .mornye-ext files on this device';
    }
    final active = extensions.where((ext) => ext.enabled).length;
    if (active == 0) {
      return '${extensions.length} installed · all off';
    }
    return '$active active of ${extensions.length} installed';
  }

  ExtensionState copyWith({
    List<InstalledExtension>? extensions,
    bool? loading,
    Set<String>? downloadingKeys,
    Map<String, String>? downloadedPaths,
    List<ExtensionDownloadItem>? downloadQueue,
  }) {
    return ExtensionState(
      extensions: extensions ?? this.extensions,
      loading: loading ?? this.loading,
      downloadingKeys: downloadingKeys ?? this.downloadingKeys,
      downloadedPaths: downloadedPaths ?? this.downloadedPaths,
      downloadQueue: downloadQueue ?? this.downloadQueue,
    );
  }
}

class ExtensionController extends Notifier<ExtensionState> {
  @override
  ExtensionState build() {
    final channel = ref.watch(extensionChannelProvider);
    if (channel.isSupported) {
      Future.microtask(_init);
    }
    return const ExtensionState();
  }

  String get _musicDir {
    try {
      return ref.read(appPathsProvider).musicDir;
    } on Object {
      return '';
    }
  }

  Future<void> _init() async {
    final channel = ref.read(extensionChannelProvider);
    final list = await channel.init(musicDir: _musicDir);
    state = state.copyWith(extensions: list, loading: false);
  }

  Future<void> refresh() async {
    final list = await ref.read(extensionChannelProvider).list();
    state = state.copyWith(extensions: list);
  }

  Future<int> discoverOnDevice() async {
    final before = state.extensions.length;
    state = state.copyWith(loading: true);
    try {
      final list = await ref
          .read(extensionChannelProvider)
          .discoverDeviceExtensions();
      state = state.copyWith(extensions: list, loading: false);
      return list.length - before;
    } finally {
      if (state.loading) state = state.copyWith(loading: false);
    }
  }

  Future<void> installFile(String path) async {
    state = state.copyWith(loading: true);
    try {
      final list = await ref.read(extensionChannelProvider).installFile(path);
      state = state.copyWith(extensions: list, loading: false);
    } finally {
      if (state.loading) state = state.copyWith(loading: false);
    }
  }

  Future<void> installFromUrl(String url) async {
    state = state.copyWith(loading: true);
    try {
      final list = await ref.read(extensionChannelProvider).installFromUrl(url);
      state = state.copyWith(extensions: list, loading: false);
    } finally {
      if (state.loading) state = state.copyWith(loading: false);
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final list = await ref
        .read(extensionChannelProvider)
        .setEnabled(id, enabled);
    state = state.copyWith(extensions: list);
  }

  Future<void> remove(String id) async {
    final list = await ref.read(extensionChannelProvider).remove(id);
    state = state.copyWith(extensions: list);
  }

  Future<void> updateSettings(
    String id,
    Map<String, Object?> settings,
  ) async {
    final list = await ref
        .read(extensionChannelProvider)
        .updateSettings(id, settings);
    state = state.copyWith(extensions: list);
  }

  Future<void> setPriority(List<String> ids) async {
    final list = await ref.read(extensionChannelProvider).setPriority(ids);
    state = state.copyWith(extensions: list);
  }

  void _upsertQueueItem(ExtensionDownloadItem item) {
    final existingIndex = state.downloadQueue.indexWhere(
      (entry) => entry.uniqueKey == item.uniqueKey,
    );
    final updated = List<ExtensionDownloadItem>.of(state.downloadQueue);
    if (existingIndex >= 0) {
      updated[existingIndex] = item;
    } else {
      updated.insert(0, item);
    }
    state = state.copyWith(downloadQueue: updated);
  }

  void removeDownloadItem(String uniqueKey) {
    state = state.copyWith(
      downloadQueue: [
        for (final item in state.downloadQueue)
          if (item.uniqueKey != uniqueKey) item,
      ],
    );
  }

  void clearFinishedDownloads() {
    state = state.copyWith(
      downloadQueue: [
        for (final item in state.downloadQueue)
          if (item.isActive) item,
      ],
    );
  }

  /// Resolves an immediate stream URL (or local file) for [track] and plays it
  /// in `NocAudioHandler`.
  Future<String?> resolvePlayableUri(ExtensionTrackResult track) async {
    final saved = state.downloadedPaths[track.uniqueKey];
    if (saved != null && saved.isNotEmpty) return saved;
    final uri = await ref
        .read(extensionChannelProvider)
        .resolveStream(track, musicDir: _musicDir);
    if (uri != null && uri.isNotEmpty && !uri.startsWith('http')) {
      state = state.copyWith(
        downloadedPaths: {...state.downloadedPaths, track.uniqueKey: uri},
      );
      try {
        await ref.read(scanControllerProvider.notifier).scan();
      } on Object {
        // In isolated widget tests.
      }
    }
    return uri;
  }

  /// Downloads [track] through the chosen [providerId] and [quality] (or
  /// enabled download extensions in priority order) into the device's music
  /// folder and triggers a library scan so it immediately appears in the
  /// library with cover art, metadata, and lyrics.
  Future<String?> downloadTrack(
    ExtensionTrackResult track, {
    String? providerId,
    String? quality,
  }) async {
    final key = track.uniqueKey;
    if (state.downloadingKeys.contains(key)) return null;
    state = state.copyWith(
      downloadingKeys: {...state.downloadingKeys, key},
    );
    _upsertQueueItem(
      ExtensionDownloadItem(
        track: track,
        status: ExtensionDownloadStatus.downloading,
        updatedAt: DateTime.now(),
      ),
    );
    try {
      final savedPath = await ref
          .read(extensionChannelProvider)
          .download(
            track,
            musicDir: _musicDir,
            providerId: providerId,
            quality: quality,
          );
      if (savedPath != null && savedPath.isNotEmpty) {
        state = state.copyWith(
          downloadingKeys: {...state.downloadingKeys}..remove(key),
          downloadedPaths: {...state.downloadedPaths, key: savedPath},
        );
        _upsertQueueItem(
          ExtensionDownloadItem(
            track: track,
            status: ExtensionDownloadStatus.completed,
            updatedAt: DateTime.now(),
            filePath: savedPath,
          ),
        );
        try {
          await ref.read(scanControllerProvider.notifier).scan();
        } on Object {
          // In isolated widget tests without a scan controller override.
        }
        return savedPath;
      }
      state = state.copyWith(
        downloadingKeys: {...state.downloadingKeys}..remove(key),
      );
      _upsertQueueItem(
        ExtensionDownloadItem(
          track: track,
          status: ExtensionDownloadStatus.failed,
          updatedAt: DateTime.now(),
          errorMessage: 'Track could not be downloaded',
        ),
      );
      return null;
    } on Object catch (e) {
      state = state.copyWith(
        downloadingKeys: {...state.downloadingKeys}..remove(key),
      );
      _upsertQueueItem(
        ExtensionDownloadItem(
          track: track,
          status: ExtensionDownloadStatus.failed,
          updatedAt: DateTime.now(),
          errorMessage: '$e',
        ),
      );
      rethrow;
    }
  }
}

final extensionControllerProvider =
    NotifierProvider<ExtensionController, ExtensionState>(
      ExtensionController.new,
    );

/// Searches installed & enabled extensions for [query]. When no extensions
/// are active, returns an empty list immediately without any channel call.
final extensionSearchResultsProvider =
    FutureProvider.autoDispose.family<List<ExtensionTrackResult>, String>((
      ref,
      query,
    ) async {
      final hasActive = ref.watch(
        extensionControllerProvider.select(
          (state) => state.hasActiveSearchOrDownload,
        ),
      );
      if (!hasActive || query.trim().isEmpty) return const [];
      return ref.watch(extensionChannelProvider).search(query.trim());
    });

/// Searches installed & enabled extensions for a [query] with an optional
/// category [filter] (`'all'`, `'tracks'`, `'albums'`, `'artists'`) and
/// optional [providerId] (specific extension ID or `'all'`).
typedef ExtensionSearchRequest = ({
  String query,
  String filter,
  String? providerId,
});

final extensionFilteredSearchProvider = FutureProvider.autoDispose
    .family<List<ExtensionTrackResult>, ExtensionSearchRequest>((
      ref,
      request,
    ) async {
      final channel = ref.watch(extensionChannelProvider);
      final hasActive = ref.watch(
        extensionControllerProvider.select(
          (state) => state.hasActiveSearchOrDownload,
        ),
      );
      final allowOnlineBuiltIn =
          channel.isSupported && request.providerId == 'ytmusic';
      if ((!hasActive && !allowOnlineBuiltIn) ||
          request.query.trim().isEmpty) {
        return const [];
      }
      return channel.search(
        request.query.trim(),
        filter: request.filter,
        providerId: request.providerId,
      );
    });
