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

const kPreinstalledMornyeExtensions = <InstalledExtension>[
  InstalledExtension(
    id: 'deezer',
    name: 'deezer',
    displayName: 'Deezer',
    version: '1.3.12',
    description: 'Deezer metadata and lossless Hi-Res downloads, with audio quality measured from each downloaded file and complete release metadata.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'flac',
        label: 'FLAC / Hi-Res',
        description: 'Best available lossless audio, up to 24-bit/192 kHz on supported tracks.',
      ),
    ],
  ),
  InstalledExtension(
    id: 'tidal-web',
    name: 'tidal-web',
    displayName: 'Tidal',
    version: '1.2.17',
    description: 'TIDAL metadata, search, and lossless/Hi-Res download provider for Mornye using TIDAL Web.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'DOLBY_ATMOS',
        label: 'Dolby Atmos',
        description: 'Require Dolby Atmos when supported; otherwise fall back to best FLAC tier',
      ),
      ExtensionQualityOption(
        id: 'HI_RES_LOSSLESS',
        label: 'HiRes FLAC',
        description:
            'Prefer 24-bit Hi-Res FLAC; fall back to 16-bit Lossless FLAC',
      ),
      ExtensionQualityOption(
        id: 'LOSSLESS',
        label: 'Lossless',
        description: 'Require TIDAL 16-bit / 44.1 kHz lossless FLAC',
      ),
      ExtensionQualityOption(
        id: 'HIGH',
        label: 'High',
        description: 'TIDAL High AAC 320 kbps',
      ),
      ExtensionQualityOption(
        id: 'LOW',
        label: 'Low',
        description: 'TIDAL Low AAC 96 kbps',
      ),
    ],
  ),
  InstalledExtension(
    id: 'qobuz-web',
    name: 'qobuz-web',
    displayName: 'Qobuz',
    version: '1.2.27',
    description: 'Qobuz metadata and 24-Bit Hi-Res / Lossless FLAC download provider with complete release metadata and original artwork.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'HI_RES_LOSSLESS',
        label: '24-Bit Max',
        description: 'Attempt the highest Qobuz 24-bit / 192 kHz quality first',
      ),
      ExtensionQualityOption(
        id: 'HI_RES',
        label: '24-Bit',
        description: 'Prefer 24-bit / 96 kHz Qobuz quality',
      ),
      ExtensionQualityOption(
        id: 'LOSSLESS',
        label: 'Lossless',
        description: 'Standard Qobuz 16-bit / 44.1 kHz lossless FLAC',
      ),
    ],
  ),
  InstalledExtension(
    id: 'jiosaavn',
    name: 'jiosaavn',
    displayName: 'JioSaavn',
    version: '1.0.10',
    description: 'Search and download JioSaavn AAC tracks, browse albums, playlists, artists, and the home feed.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'AAC_320',
        label: 'AAC 320 kbps',
        description: 'Highest quality JioSaavn offers',
      ),
      ExtensionQualityOption(
        id: 'AAC_160',
        label: 'AAC 160 kbps',
        description: 'Good quality, smaller files',
      ),
      ExtensionQualityOption(
        id: 'AAC_96',
        label: 'AAC 96 kbps',
        description: 'Data saver',
      ),
      ExtensionQualityOption(
        id: 'AAC_48',
        label: 'AAC 48 kbps',
        description: 'Low quality',
      ),
      ExtensionQualityOption(
        id: 'AAC_12',
        label: 'AAC 12 kbps',
        description: 'Lowest bitrate',
      ),
    ],
  ),
  InstalledExtension(
    id: 'ytmusic-spotiflac',
    name: 'ytmusic-spotiflac',
    displayName: 'YouTube Music',
    version: '2.4.8',
    description: 'YouTube Music metadata and download provider with native album, artist, explicit, release, and song-credit metadata.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'best',
        label: 'Best Audio',
        description: 'Opus/M4A audio direct from YouTube Music',
      ),
    ],
  ),
  InstalledExtension(
    id: 'soundcloud',
    name: 'soundcloud',
    displayName: 'SoundCloud',
    version: '1.0.15',
    description: 'SoundCloud metadata and download provider. Search tracks, albums, playlists, artists. Downloads via direct SoundCloud streams.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'aac_160',
        label: 'AAC up to 160kbps',
        description:
            'Current SoundCloud quality, saved as M4A without re-encoding',
      ),
    ],
  ),
  InstalledExtension(
    id: 'amazon',
    name: 'amazon',
    displayName: 'Amazon Music',
    version: '2.3.19',
    description: 'Amazon Music metadata & download provider for Mornye. Downloads lossless FLAC and Dolby Atmos audio.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'best',
        label: 'FLAC Best Available',
        description: 'Best available quality (up to 24-bit/192kHz)',
      ),
      ExtensionQualityOption(
        id: 'opus',
        label: 'Opus 320kbps',
        description: 'High quality Opus audio at 320kbps',
      ),
      ExtensionQualityOption(
        id: 'eac3',
        label: 'Dolby Digital Plus',
        description: 'Dolby Digital Plus surround sound (E-AC-3)',
      ),
      ExtensionQualityOption(
        id: 'ac4',
        label: 'Dolby Atmos (AC-4)',
        description: 'Dolby Atmos immersive audio (AC-4)',
      ),
    ],
  ),
  InstalledExtension(
    id: 'beatport',
    name: 'beatport',
    displayName: 'Beatport',
    version: '1.0.2',
    description: 'Beatport track, artist and release search, artist discographies, and original FLAC or AAC 256 kbps downloads.',
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
    qualityOptions: [
      ExtensionQualityOption(
        id: 'LOSSLESS',
        label: 'FLAC Lossless',
        description: 'Original lossless audio.',
      ),
      ExtensionQualityOption(
        id: 'HIGH',
        label: 'AAC 256 kbps',
        description: 'Original AAC in M4A, without re-encoding.',
      ),
    ],
  ),
  InstalledExtension(
    id: 'spotify-web',
    name: 'spotify-web',
    displayName: 'Spotify Web',
    version: '1.10.6',
    description: 'Spotify metadata provider with complete native release, disc, catalog ID, credits, and artwork metadata.',
    hasMetadataProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
  ),
  InstalledExtension(
    id: 'apple-music',
    name: 'apple-music',
    displayName: 'Apple Music',
    version: '1.4.17',
    description: 'Apple Music metadata and lyrics provider with guarded track matching and complete release metadata.',
    hasMetadataProvider: true,
    hasLyricsProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
  ),
  InstalledExtension(
    id: 'bugs-music',
    name: 'bugs-music',
    displayName: 'Bugs Music',
    version: '2.0.7',
    description: 'Bugs Music metadata, artist catalogs, realtime/daily/weekly charts, genre charts, and URL imports.',
    hasMetadataProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
  ),
  InstalledExtension(
    id: 'melon-music',
    name: 'melon-music',
    displayName: 'Melon Music',
    version: '2.0.7',
    description: 'Melon Music metadata, period and genre charts, HOT100, album and artist catalogs, and URL imports.',
    hasMetadataProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
  ),
  InstalledExtension(
    id: 'genie-music',
    name: 'genie-music',
    displayName: 'Genie Music',
    version: '2.0.7',
    description: 'Genie Music metadata, paginated artist catalogs, period TOP200 charts, genre charts, and URL imports.',
    hasMetadataProvider: true,
    hasCustomSearch: true,
    hasUrlHandler: true,
  ),
  InstalledExtension(
    id: 'jellyfin',
    name: 'jellyfin',
    displayName: 'Jellyfin',
    version: '1.1.1',
    description: 'Use your own Jellyfin server as a search provider, download source, lyrics source and home feed.',
    enabled: false,
    hasMetadataProvider: true,
    hasDownloadProvider: true,
    hasLyricsProvider: true,
    hasCustomSearch: true,
  ),
];

class ExtensionController extends Notifier<ExtensionState> {
  @override
  ExtensionState build() {
    final channel = ref.watch(extensionChannelProvider);
    final isRealAndroidChannel =
        channel.isSupported && channel.runtimeType == ExtensionChannel;
    if (channel.isSupported) {
      Future.microtask(_init);
    }
    return ExtensionState(
      extensions: isRealAndroidChannel
          ? kPreinstalledMornyeExtensions
          : const [],
    );
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
    final isRealAndroidChannel =
        channel.isSupported && channel.runtimeType == ExtensionChannel;
    final list = await channel.init(musicDir: _musicDir);
    if (list.isNotEmpty || !isRealAndroidChannel) {
      state = state.copyWith(extensions: list, loading: false);
    } else {
      state = state.copyWith(
        extensions: kPreinstalledMornyeExtensions,
        loading: false,
      );
    }
  }

  Future<void> refresh() async {
    final list = await ref.read(extensionChannelProvider).list();
    if (list.isNotEmpty) {
      state = state.copyWith(extensions: list);
    }
  }

  Future<int> checkForUpdates() async {
    state = state.copyWith(loading: true);
    try {
      final list = await ref.read(extensionChannelProvider).checkUpdates();
      if (list.isNotEmpty) {
        state = state.copyWith(extensions: list, loading: false);
      } else {
        state = state.copyWith(loading: false);
      }
      return state.extensions.where((ext) => ext.hasUpdate).length;
    } finally {
      if (state.loading) state = state.copyWith(loading: false);
    }
  }

  Future<void> updateFromRegistry({String? id}) async {
    state = state.copyWith(loading: true);
    try {
      final list = await ref
          .read(extensionChannelProvider)
          .updateFromRegistry(id: id);
      if (list.isNotEmpty) {
        state = state.copyWith(extensions: list, loading: false);
      } else {
        state = state.copyWith(loading: false);
      }
    } finally {
      if (state.loading) state = state.copyWith(loading: false);
    }
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

  Future<void> updateSettings(String id, Map<String, Object?> settings) async {
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
    state = state.copyWith(downloadingKeys: {...state.downloadingKeys, key});
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
final extensionSearchResultsProvider = FutureProvider.autoDispose
    .family<List<ExtensionTrackResult>, String>((ref, query) async {
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
      if ((!hasActive && !allowOnlineBuiltIn) || request.query.trim().isEmpty) {
        return const [];
      }
      return channel.search(
        request.query.trim(),
        filter: request.filter,
        providerId: request.providerId,
      );
    });
