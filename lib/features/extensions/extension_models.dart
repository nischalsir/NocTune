import 'package:flutter/foundation.dart';

/// A setting declared in an extension's `manifest.json`.
@immutable
class ExtensionSettingField {
  const ExtensionSettingField({
    required this.key,
    required this.type,
    required this.label,
    this.description = '',
    this.required = false,
    this.secret = false,
    this.defaultValue,
    this.value,
    this.options = const [],
    this.action = '',
  });

  factory ExtensionSettingField.fromMap(Map<Object?, Object?> map) {
    return ExtensionSettingField(
      key: (map['key'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'string',
      label: (map['label'] as String?) ?? (map['key'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      required: (map['required'] as bool?) ?? false,
      secret: (map['secret'] as bool?) ?? false,
      defaultValue: map['default'],
      value: map['value'],
      options: [
        for (final item in (map['options'] as List<Object?>?) ?? const [])
          if (item is String) item,
      ],
      action: (map['action'] as String?) ?? '',
    );
  }

  final String key;
  final String type;
  final String label;
  final String description;
  final bool required;
  final bool secret;
  final Object? defaultValue;
  final Object? value;
  final List<String> options;
  final String action;
}

/// A quality option declared by a download extension.
@immutable
class ExtensionQualityOption {
  const ExtensionQualityOption({
    required this.id,
    required this.label,
    this.description = '',
  });

  factory ExtensionQualityOption.fromMap(Map<Object?, Object?> map) {
    final id = (map['id'] as String?) ?? '';
    return ExtensionQualityOption(
      id: id,
      label: (map['label'] as String?) ?? id,
      description: (map['description'] as String?) ?? '',
    );
  }

  final String id;
  final String label;
  final String description;
}

/// An installed Mornye / SpotiFLAC extension package (`.spotiflac-ext`,
/// `.sflx`, or `.mornye-ext`).
@immutable
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    required this.name,
    required this.displayName,
    required this.version,
    this.description = '',
    this.enabled = true,
    this.status = 'loaded',
    this.errorMessage,
    this.hasMetadataProvider = false,
    this.hasDownloadProvider = false,
    this.hasLyricsProvider = false,
    this.hasCustomSearch = false,
    this.hasUrlHandler = false,
    this.searchPlaceholder = '',
    this.settings = const [],
    this.qualityOptions = const [],
  });

  factory InstalledExtension.fromMap(Map<Object?, Object?> map) {
    final id = (map['id'] as String?) ?? '';
    final name = (map['name'] as String?) ?? id;
    return InstalledExtension(
      id: id,
      name: name,
      displayName: (map['displayName'] as String?) ?? name,
      version: (map['version'] as String?) ?? '1.0.0',
      description: (map['description'] as String?) ?? '',
      enabled: (map['enabled'] as bool?) ?? true,
      status: (map['status'] as String?) ?? 'loaded',
      errorMessage: map['errorMessage'] as String?,
      hasMetadataProvider: (map['hasMetadataProvider'] as bool?) ?? false,
      hasDownloadProvider: (map['hasDownloadProvider'] as bool?) ?? false,
      hasLyricsProvider: (map['hasLyricsProvider'] as bool?) ?? false,
      hasCustomSearch: (map['hasCustomSearch'] as bool?) ?? false,
      hasUrlHandler: (map['hasUrlHandler'] as bool?) ?? false,
      searchPlaceholder: (map['searchPlaceholder'] as String?) ?? '',
      settings: [
        for (final item in (map['settings'] as List<Object?>?) ?? const [])
          if (item is Map<Object?, Object?>)
            ExtensionSettingField.fromMap(item),
      ],
      qualityOptions: [
        for (final item
            in (map['qualityOptions'] as List<Object?>?) ?? const [])
          if (item is Map<Object?, Object?>)
            ExtensionQualityOption.fromMap(item),
      ],
    );
  }

  final String id;
  final String name;
  final String displayName;
  final String version;
  final String description;
  final bool enabled;
  final String status;
  final String? errorMessage;
  final bool hasMetadataProvider;
  final bool hasDownloadProvider;
  final bool hasLyricsProvider;
  final bool hasCustomSearch;
  final bool hasUrlHandler;
  final String searchPlaceholder;
  final List<ExtensionSettingField> settings;
  final List<ExtensionQualityOption> qualityOptions;

  /// Human-readable summary of what this extension provides.
  String get capabilitySummary {
    final roles = <String>[
      if (hasMetadataProvider || hasCustomSearch) 'Search',
      if (hasDownloadProvider) 'Download',
      if (hasLyricsProvider) 'Lyrics',
      if (hasUrlHandler) 'Links',
    ];
    final prefix = 'v$version';
    return roles.isEmpty ? prefix : '$prefix · ${roles.join(' · ')}';
  }
}

/// A track, album, or artist returned by an extension search or URL resolution.
@immutable
class ExtensionTrackResult {
  const ExtensionTrackResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.duration = Duration.zero,
    this.coverUrl = '',
    this.isrc = '',
    this.providerId = '',
    this.providerName = '',
    this.audioQuality = '',
    this.itemType = 'track',
    this.totalTracks = 0,
    this.releaseDate = '',
    this.raw = const {},
  });

  factory ExtensionTrackResult.fromMap(Map<Object?, Object?> map) {
    final rawMap = <String, Object?>{
      for (final entry in map.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final durationMs = (map['duration_ms'] as num?)?.toInt() ?? 0;
    final rawType = ((map['item_type'] as String?) ?? 'track')
        .trim()
        .toLowerCase();
    final itemType = switch (rawType) {
      'album' || 'albums' => 'album',
      'artist' || 'artists' => 'artist',
      _ => 'track',
    };
    return ExtensionTrackResult(
      id: (map['id'] as String?) ?? '',
      title: (map['title'] as String?) ?? (map['name'] as String?) ?? 'Unknown',
      artist:
          (map['artist'] as String?) ?? (map['artists'] as String?) ?? '',
      album:
          (map['album'] as String?) ?? (map['album_name'] as String?) ?? '',
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      coverUrl: (map['cover_url'] as String?) ?? '',
      isrc: (map['isrc'] as String?) ?? '',
      providerId: (map['provider_id'] as String?) ?? '',
      providerName: (map['provider_name'] as String?) ?? '',
      audioQuality: (map['audio_quality'] as String?) ?? '',
      itemType: itemType,
      totalTracks: (map['total_tracks'] as num?)?.toInt() ?? 0,
      releaseDate: (map['release_date'] as String?) ?? '',
      raw: rawMap,
    );
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String coverUrl;
  final String isrc;
  final String providerId;
  final String providerName;
  final String audioQuality;
  final String itemType;
  final int totalTracks;
  final String releaseDate;
  final Map<String, Object?> raw;

  bool get isTrack => itemType == 'track';
  bool get isAlbum => itemType == 'album';
  bool get isArtist => itemType == 'artist';

  String get uniqueKey => '$providerId:$itemType:$id';
}

/// Full album details and tracklist fetched from an extension via `getAlbum`.
@immutable
class ExtensionAlbumDetails {
  const ExtensionAlbumDetails({
    required this.id,
    required this.name,
    required this.artist,
    this.coverUrl = '',
    this.releaseDate = '',
    this.providerId = '',
    this.providerName = '',
    this.tracks = const [],
  });

  factory ExtensionAlbumDetails.fromMap(Map<Object?, Object?> map) {
    return ExtensionAlbumDetails(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      artist: (map['artist'] as String?) ?? '',
      coverUrl: (map['cover_url'] as String?) ?? '',
      releaseDate: (map['release_date'] as String?) ?? '',
      providerId: (map['provider_id'] as String?) ?? '',
      providerName: (map['provider_name'] as String?) ?? '',
      tracks: [
        for (final item in (map['tracks'] as List<Object?>?) ?? const [])
          if (item is Map<Object?, Object?>) ExtensionTrackResult.fromMap(item),
      ],
    );
  }

  final String id;
  final String name;
  final String artist;
  final String coverUrl;
  final String releaseDate;
  final String providerId;
  final String providerName;
  final List<ExtensionTrackResult> tracks;
}

/// Artist top tracks and albums fetched from an extension via `getArtist`.
@immutable
class ExtensionArtistDetails {
  const ExtensionArtistDetails({
    required this.id,
    required this.name,
    this.coverUrl = '',
    this.providerId = '',
    this.providerName = '',
    this.topTracks = const [],
    this.albums = const [],
  });

  factory ExtensionArtistDetails.fromMap(Map<Object?, Object?> map) {
    return ExtensionArtistDetails(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      coverUrl: (map['cover_url'] as String?) ?? '',
      providerId: (map['provider_id'] as String?) ?? '',
      providerName: (map['provider_name'] as String?) ?? '',
      topTracks: [
        for (final item in (map['top_tracks'] as List<Object?>?) ?? const [])
          if (item is Map<Object?, Object?>) ExtensionTrackResult.fromMap(item),
      ],
      albums: [
        for (final item in (map['albums'] as List<Object?>?) ?? const [])
          if (item is Map<Object?, Object?>) ExtensionTrackResult.fromMap(item),
      ],
    );
  }

  final String id;
  final String name;
  final String coverUrl;
  final String providerId;
  final String providerName;
  final List<ExtensionTrackResult> topTracks;
  final List<ExtensionTrackResult> albums;
}

/// Lifecycle state of an extension track download in the download queue.
enum ExtensionDownloadStatus { queued, downloading, completed, failed }

/// An entry in the extension download queue / history list.
@immutable
class ExtensionDownloadItem {
  const ExtensionDownloadItem({
    required this.track,
    required this.status,
    required this.updatedAt,
    this.filePath,
    this.errorMessage,
  });

  final ExtensionTrackResult track;
  final ExtensionDownloadStatus status;
  final DateTime updatedAt;
  final String? filePath;
  final String? errorMessage;

  String get uniqueKey => track.uniqueKey;

  bool get isActive =>
      status == ExtensionDownloadStatus.queued ||
      status == ExtensionDownloadStatus.downloading;

  ExtensionDownloadItem copyWith({
    ExtensionTrackResult? track,
    ExtensionDownloadStatus? status,
    DateTime? updatedAt,
    String? filePath,
    String? errorMessage,
  }) {
    return ExtensionDownloadItem(
      track: track ?? this.track,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage,
    );
  }
}
