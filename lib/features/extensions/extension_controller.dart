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
  });

  final List<InstalledExtension> extensions;
  final bool loading;
  final Set<String> downloadingKeys;
  final Map<String, String> downloadedPaths;

  /// True when at least one enabled extension can search or download tracks.
  bool get hasActiveSearchOrDownload => extensions.any(
    (ext) =>
        ext.enabled &&
        (ext.hasMetadataProvider ||
            ext.hasCustomSearch ||
            ext.hasDownloadProvider ||
            ext.hasUrlHandler),
  );

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
  }) {
    return ExtensionState(
      extensions: extensions ?? this.extensions,
      loading: loading ?? this.loading,
      downloadingKeys: downloadingKeys ?? this.downloadingKeys,
      downloadedPaths: downloadedPaths ?? this.downloadedPaths,
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

  /// Downloads [track] through the enabled download extensions into the
  /// device's music folder and triggers a library scan so it immediately
  /// appears in the library.
  Future<String?> downloadTrack(ExtensionTrackResult track) async {
    final key = track.uniqueKey;
    if (state.downloadingKeys.contains(key)) return null;
    state = state.copyWith(
      downloadingKeys: {...state.downloadingKeys, key},
    );
    try {
      final savedPath = await ref
          .read(extensionChannelProvider)
          .download(track, musicDir: _musicDir);
      if (savedPath != null && savedPath.isNotEmpty) {
        state = state.copyWith(
          downloadingKeys: {...state.downloadingKeys}..remove(key),
          downloadedPaths: {...state.downloadedPaths, key: savedPath},
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
      return null;
    } on Object {
      state = state.copyWith(
        downloadingKeys: {...state.downloadingKeys}..remove(key),
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
