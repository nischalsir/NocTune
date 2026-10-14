import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Jamendo client id, set at build time with
/// `--dart-define=NOCTUNE_JAMENDO_CLIENT_ID=…`. When it is empty, as it is
/// by default, online search is off and no request is made.
const kJamendoClientId = String.fromEnvironment('NOCTUNE_JAMENDO_CLIENT_ID');

/// Why an online search gave no fresh results.
enum OnlineFailure {
  /// No connection, or it timed out.
  offline,

  /// Jamendo asked NocTune to slow down.
  rateLimited,

  /// Jamendo answered with an error, or with something unreadable.
  unavailable,
}

class OnlineSearchException implements Exception {
  const OnlineSearchException(this.failure, [this.message = '']);

  final OnlineFailure failure;
  final String message;

  @override
  String toString() => 'OnlineSearchException($failure, $message)';
}

/// A free track on Jamendo, published under a Creative Commons licence.
@immutable
class OnlineTrack {
  const OnlineTrack({
    required this.id,
    required this.title,
    required this.streamUrl,
    this.artist,
    this.album,
    this.duration = Duration.zero,
    this.imageUrl,
    this.downloadUrl,
    this.licenceUrl,
  });

  /// Reads one entry of Jamendo's track list. Returns null for an entry
  /// with nothing to play.
  static OnlineTrack? fromJamendo(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}';
    final title = json['name'];
    final stream = _https(json['audio']);
    if (id.isEmpty || title is! String || stream == null) return null;
    return OnlineTrack(
      id: id,
      title: title,
      streamUrl: stream,
      artist: _text(json['artist_name']),
      album: _text(json['album_name']),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      imageUrl: _https(json['album_image']) ?? _https(json['image']),
      downloadUrl: json['audiodownload_allowed'] == true
          ? _https(json['audiodownload'])
          : null,
      licenceUrl: _text(json['license_ccurl']),
    );
  }

  /// Reads what [toJson] wrote.
  factory OnlineTrack.fromJson(Map<String, Object?> json) => OnlineTrack(
    id: json['id']! as String,
    title: json['title']! as String,
    streamUrl: Uri.parse(json['stream']! as String),
    artist: json['artist'] as String?,
    album: json['album'] as String?,
    duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
    imageUrl: switch (json['image']) {
      final String url => Uri.parse(url),
      _ => null,
    },
    downloadUrl: switch (json['download']) {
      final String url => Uri.parse(url),
      _ => null,
    },
    licenceUrl: json['licence'] as String?,
  );

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final Duration duration;

  /// Where the player streams it from.
  final Uri streamUrl;
  final Uri? imageUrl;

  /// The file to keep for offline listening, when Jamendo allows it.
  final Uri? downloadUrl;

  /// The Creative Commons licence it is published under.
  final String? licenceUrl;

  Map<String, Object?> toJson() => {
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

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static Uri? _https(Object? value) {
    final url = value is String ? Uri.tryParse(value) : null;
    return url != null && url.scheme == 'https' && url.host.isNotEmpty
        ? url
        : null;
  }
}

typedef JamendoResponse = ({int status, String body});

/// Downloads one answer from Jamendo. Replaced with a fake in tests.
typedef JamendoFetch = Future<JamendoResponse> Function(Uri url);

Future<JamendoResponse> fetchOverHttps(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final request = await client.getUrl(url);
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

/// Searches Jamendo's catalogue of free music.
class JamendoClient {
  JamendoClient({required this.clientId, this.fetch = fetchOverHttps});

  final String clientId;
  final JamendoFetch fetch;

  /// How many tracks one search returns.
  static const limit = 20;

  /// Throws [OnlineSearchException] when Jamendo can't be asked or can't
  /// answer; an empty list means it answered with no match.
  Future<List<OnlineTrack>> search(String query) async {
    final url = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
      'client_id': clientId,
      'format': 'json',
      'limit': '$limit',
      'search': query.trim(),
      'audioformat': 'mp32',
      'imagesize': '300',
    });
    final JamendoResponse response;
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

    final Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      throw const OnlineSearchException(
        OnlineFailure.unavailable,
        'An unreadable answer',
      );
    }
    if (json is! Map<String, Object?>) {
      throw const OnlineSearchException(
        OnlineFailure.unavailable,
        'An unreadable answer',
      );
    }
    final headers = json['headers'];
    if (headers is! Map<String, Object?> || headers['status'] != 'success') {
      final message = headers is Map<String, Object?>
          ? '${headers['error_message'] ?? ''}'
          : '';
      throw OnlineSearchException(OnlineFailure.unavailable, message);
    }
    final results = json['results'];
    return [
      if (results is List)
        for (final entry in results.whereType<Map<String, Object?>>())
          ?OnlineTrack.fromJamendo(entry),
    ];
  }
}
