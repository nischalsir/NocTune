import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The services NocTune finds music on.
enum OnlineSourceId {
  jamendo,
  audius,
  archive;

  String get label => switch (this) {
    jamendo => 'Jamendo',
    audius => 'Audius',
    archive => 'Internet Archive',
  };

  /// The small mark on each of its results.
  String get badge => switch (this) {
    jamendo => 'JAMENDO',
    audius => 'AUDIUS',
    archive => 'ARCHIVE',
  };
}

/// Why an online search gave no fresh results.
enum OnlineFailure {
  /// No connection, or it timed out.
  offline,

  /// The service asked NocTune to slow down.
  rateLimited,

  /// The service answered with an error, or with something unreadable.
  unavailable,
}

class OnlineSearchException implements Exception {
  const OnlineSearchException(this.failure, [this.message = '']);

  final OnlineFailure failure;
  final String message;

  @override
  String toString() => 'OnlineSearchException($failure, $message)';
}

/// One result of an online search: a song, or an album or show to open.
sealed class OnlineItem {
  const OnlineItem();

  /// Reads what [toJson] wrote.
  static OnlineItem fromJson(Map<String, Object?> json) =>
      json['type'] == 'album'
      ? OnlineAlbum.fromJson(json)
      : OnlineTrack.fromJson(json);

  OnlineSourceId get source;
  String get id;
  String get title;
  Uri? get imageUrl;

  /// Unique across sources.
  String get key => '${source.name}:$id';

  Map<String, Object?> toJson();
}

/// A song found online.
@immutable
final class OnlineTrack extends OnlineItem {
  const OnlineTrack({
    required this.id,
    required this.title,
    required this.streamUrl,
    this.source = OnlineSourceId.jamendo,
    this.artist,
    this.album,
    this.duration = Duration.zero,
    this.imageUrl,
    this.downloadUrl,
    this.licenceUrl,
  });

  /// Reads what [toJson] wrote. Saved before there was more than one
  /// source, a track has no source and is Jamendo's.
  factory OnlineTrack.fromJson(Map<String, Object?> json) => OnlineTrack(
    source: _sourceNamed(json['source']),
    id: json['id']! as String,
    title: json['title']! as String,
    streamUrl: Uri.parse(json['stream']! as String),
    artist: json['artist'] as String?,
    album: json['album'] as String?,
    duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
    imageUrl: _url(json['image']),
    downloadUrl: _url(json['download']),
    licenceUrl: json['licence'] as String?,
  );

  @override
  final OnlineSourceId source;
  @override
  final String id;
  @override
  final String title;
  final String? artist;
  final String? album;
  final Duration duration;

  /// Where the player streams it from.
  final Uri streamUrl;
  @override
  final Uri? imageUrl;

  /// The file to keep for offline listening, when the service allows it.
  final Uri? downloadUrl;

  /// The licence it is published under.
  final String? licenceUrl;

  @override
  Map<String, Object?> toJson() => {
    'source': source.name,
    'id': id,
    'title': title,
    'stream': '$streamUrl',
    'artist': artist,
    'album': album,
    'durationMs': duration.inMilliseconds,
    'image': imageUrl?.toString(),
    'download': downloadUrl?.toString(),
    'licence': licenceUrl,
  };
}

enum OnlineAlbumKind { show, album }

/// An album or a recorded show, whose tracks are fetched when it is opened.
@immutable
final class OnlineAlbum extends OnlineItem {
  const OnlineAlbum({
    required this.source,
    required this.id,
    required this.title,
    required this.kind,
    this.creator,
    this.imageUrl,
    this.licenceUrl,
  });

  factory OnlineAlbum.fromJson(Map<String, Object?> json) => OnlineAlbum(
    source: _sourceNamed(json['source']),
    id: json['id']! as String,
    title: json['title']! as String,
    kind: json['kind'] == OnlineAlbumKind.show.name
        ? OnlineAlbumKind.show
        : OnlineAlbumKind.album,
    creator: json['creator'] as String?,
    imageUrl: _url(json['image']),
    licenceUrl: json['licence'] as String?,
  );

  @override
  final OnlineSourceId source;
  @override
  final String id;
  @override
  final String title;
  final OnlineAlbumKind kind;
  final String? creator;
  @override
  final Uri? imageUrl;
  final String? licenceUrl;

  @override
  Map<String, Object?> toJson() => {
    'type': 'album',
    'source': source.name,
    'id': id,
    'title': title,
    'kind': kind.name,
    'creator': creator,
    'image': imageUrl?.toString(),
    'licence': licenceUrl,
  };

  @override
  bool operator ==(Object other) => other is OnlineAlbum && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A service NocTune can search.
abstract interface class OnlineSource {
  OnlineSourceId get id;

  /// Throws [OnlineSearchException] when the service can't be asked or
  /// can't answer; an empty list means it answered with no match.
  Future<List<OnlineItem>> search(String words);
}

typedef OnlineResponse = ({int status, String body});

/// Downloads one answer from a service. Replaced with a fake in tests.
typedef OnlineFetch = Future<OnlineResponse> Function(Uri url);

Future<OnlineResponse> fetchOverHttps(
  Uri url, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

/// Asks [url] and reads its JSON, turning every way that can fail into an
/// [OnlineSearchException].
Future<Object?> fetchJson(OnlineFetch fetch, Uri url) async {
  final OnlineResponse response;
  try {
    response = await fetch(url);
  } on SocketException {
    throw const OnlineSearchException(OnlineFailure.offline);
  } on HandshakeException {
    throw const OnlineSearchException(OnlineFailure.offline);
  } on TimeoutException {
    throw const OnlineSearchException(OnlineFailure.offline);
  } on HttpException catch (error) {
    throw OnlineSearchException(OnlineFailure.unavailable, error.message);
  } on IOException catch (error) {
    throw OnlineSearchException(OnlineFailure.unavailable, '$error');
  } on FormatException {
    // A body that isn't text.
    throw const OnlineSearchException(
      OnlineFailure.unavailable,
      'An unreadable answer',
    );
  }
  if (response.status == 429) {
    throw const OnlineSearchException(OnlineFailure.rateLimited);
  }
  if (response.status != 200) {
    throw OnlineSearchException(
      OnlineFailure.unavailable,
      'HTTP ${response.status}',
    );
  }
  try {
    return jsonDecode(response.body);
  } on FormatException {
    throw const OnlineSearchException(
      OnlineFailure.unavailable,
      'An unreadable answer',
    );
  }
}

/// [value] as text, or null when it is not text or is blank.
String? text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

/// [value] as an https address, or null.
Uri? httpsUrl(Object? value) {
  final url = value is String ? Uri.tryParse(value) : null;
  return url != null && url.scheme == 'https' && url.host.isNotEmpty
      ? url
      : null;
}

OnlineSourceId _sourceNamed(Object? name) => OnlineSourceId.values.firstWhere(
  (source) => source.name == name,
  orElse: () => OnlineSourceId.jamendo,
);

Uri? _url(Object? value) => value is String ? Uri.parse(value) : null;
