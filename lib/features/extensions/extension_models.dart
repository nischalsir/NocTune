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

/// A track returned by an extension search or URL resolution.
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
    this.raw = const {},
  });

  factory ExtensionTrackResult.fromMap(Map<Object?, Object?> map) {
    final rawMap = <String, Object?>{
      for (final entry in map.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final durationMs = (map['duration_ms'] as num?)?.toInt() ?? 0;
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
  final Map<String, Object?> raw;

  String get uniqueKey => '$providerId:$id';
}
