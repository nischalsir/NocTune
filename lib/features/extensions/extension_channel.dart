import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'extension_models.dart';

/// Platform bridge to `noctune/extensions` on Android. Replaced with a fake
/// in widget and unit tests.
class ExtensionChannel {
  const ExtensionChannel();

  static const _channel = MethodChannel('noctune/extensions');

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<List<InstalledExtension>> init({required String musicDir}) async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('init', {
        'musicDir': musicDir,
      });
      return _parseExtensions(raw);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<InstalledExtension>> list() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('list');
      return _parseExtensions(raw);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<InstalledExtension>> discoverDeviceExtensions() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>(
      'discoverDeviceExtensions',
    );
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> installFile(String path) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('installFile', {
      'path': path,
    });
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> installFromUrl(String url) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('installFromUrl', {
      'url': url,
    });
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> setEnabled(String id, bool enabled) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('setEnabled', {
      'id': id,
      'enabled': enabled,
    });
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> remove(String id) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('remove', {'id': id});
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> updateSettings(
    String id,
    Map<String, Object?> settings,
  ) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('updateSettings', {
      'id': id,
      'settings': settings,
    });
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> setPriority(List<String> ids) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('setPriority', {
      'ids': ids,
    });
    return _parseExtensions(raw);
  }

  Future<List<InstalledExtension>> checkUpdates() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('checkUpdates');
      return _parseExtensions(raw);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<InstalledExtension>> updateFromRegistry({String? id}) async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('updateFromRegistry', {
      if (id != null && id.isNotEmpty) 'id': id,
    });
    return _parseExtensions(raw);
  }

  Future<List<ExtensionTrackResult>> search(
    String query, {
    int limit = 50,
    String? filter,
    String? providerId,
  }) async {
    if (!isSupported || query.trim().isEmpty) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('search', {
        'query': query.trim(),
        'limit': limit,
        'filter': ?filter,
        'providerId': ?providerId,
      });
      if (raw == null) return const [];
      return [
        for (final item in raw)
          if (item is Map<Object?, Object?>) ExtensionTrackResult.fromMap(item),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<ExtensionAlbumDetails?> getAlbum({
    required String providerId,
    required String albumId,
  }) async {
    if (!isSupported || providerId.isEmpty || albumId.isEmpty) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('getAlbum', {
        'providerId': providerId,
        'albumId': albumId,
      });
      if (raw == null || raw.isEmpty) return null;
      return ExtensionAlbumDetails.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ExtensionArtistDetails?> getArtist({
    required String providerId,
    required String artistId,
  }) async {
    if (!isSupported || providerId.isEmpty || artistId.isEmpty) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getArtist',
        {'providerId': providerId, 'artistId': artistId},
      );
      if (raw == null || raw.isEmpty) return null;
      return ExtensionArtistDetails.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<String?> download(
    ExtensionTrackResult track, {
    required String musicDir,
    String? providerId,
    String? quality,
  }) async {
    if (!isSupported) return null;
    final raw = await _channel.invokeMapMethod<Object?, Object?>('download', {
      'track': track.raw,
      'musicDir': musicDir,
      if (providerId != null && providerId.isNotEmpty) 'providerId': providerId,
      if (quality != null && quality.isNotEmpty) 'quality': quality,
    });
    return raw?['filePath'] as String?;
  }

  static int? _lastProxyPort;
  static String? _lastCodec;
  static int? _lastBitrate;
  static int? _lastSampleRate;
  static int? _lastDurationMs;

  String? get lastResolvedCodec => _lastCodec;
  int? get lastResolvedBitrate => _lastBitrate;
  int? get lastResolvedSampleRate => _lastSampleRate;
  int? get lastResolvedDurationMs => _lastDurationMs;

  Future<String?> resolveStream(
    ExtensionTrackResult track, {
    required String musicDir,
  }) async {
    if (!isSupported) return null;
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'resolveStream',
      {'track': track.raw, 'musicDir': musicDir},
    );
    final port = (raw?['proxyPort'] as num?)?.toInt();
    if (port != null && port > 0) {
      _lastProxyPort = port;
    }
    _lastCodec = raw?['codec'] as String?;
    _lastBitrate = (raw?['bitrate'] as num?)?.toInt();
    _lastSampleRate = (raw?['sampleRate'] as num?)?.toInt();
    _lastDurationMs = (raw?['durationMs'] as num?)?.toInt();
    return raw?['uri'] as String?;
  }

  /// Builds a local lazy-resolved stream URL for an upcoming track in the
  /// online play queue so ExoPlayer resolves it on demand when skipped to.
  String buildLazyStreamUri(ExtensionTrackResult track) {
    final port = _lastProxyPort;
    final query = Uri(
      queryParameters: {
        'id': track.id,
        'provider_id': track.providerId,
        'title': track.title,
        'artist': track.artist,
        'duration_ms': '${track.duration.inMilliseconds}',
      },
    ).query;
    if (port != null && port > 0) {
      return 'http://127.0.0.1:$port/ytlazy?$query';
    }
    return 'http://127.0.0.1/ytlazy?$query';
  }

  Future<String?> fetchLyrics({
    required String title,
    required String artist,
    required String album,
    required Duration duration,
  }) async {
    if (!isSupported || title.trim().isEmpty) return null;
    try {
      final lrc = await _channel.invokeMethod<String>('fetchLyrics', {
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': duration.inMilliseconds,
      });
      return (lrc == null || lrc.trim().isEmpty) ? null : lrc.trim();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ExtensionHomeFeed> getHomeFeed({
    List<String> seedArtists = const [],
    List<String> seedTracks = const [],
    String? providerId,
    String? chipParams,
  }) async {
    if (!isSupported) return const ExtensionHomeFeed();
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getHomeFeed',
        {
          'seedArtists': seedArtists,
          'seedTracks': seedTracks,
          if (providerId != null && providerId.isNotEmpty)
            'providerId': providerId,
          if (chipParams != null && chipParams.isNotEmpty)
            'chipParams': chipParams,
        },
      );
      if (raw == null || raw.isEmpty) return const ExtensionHomeFeed();
      return ExtensionHomeFeed.fromMap(raw);
    } on PlatformException {
      return const ExtensionHomeFeed();
    } on MissingPluginException {
      return const ExtensionHomeFeed();
    }
  }

  List<InstalledExtension> _parseExtensions(List<Object?>? raw) {
    if (raw == null) return const [];
    return [
      for (final item in raw)
        if (item is Map<Object?, Object?>) InstalledExtension.fromMap(item),
    ];
  }
}
