import 'online_source.dart';

/// Jamendo client id, set at build time with
/// `--dart-define=NOCTUNE_JAMENDO_CLIENT_ID=…`. When it is empty, as it is
/// by default, Jamendo is never asked.
const kJamendoClientId = String.fromEnvironment('NOCTUNE_JAMENDO_CLIENT_ID');

/// Searches Jamendo's catalogue of free music, published under Creative
/// Commons licences.
class JamendoSource implements OnlineSource {
  JamendoSource({
    required this.clientId,
    this.fetch = fetchOverHttps,
    this.retryDelay = const Duration(seconds: 1),
  });

  final String clientId;
  final OnlineFetch fetch;

  /// Jamendo sometimes answers a search with nothing when the same search
  /// found tracks a moment before. An empty answer is asked once more,
  /// after this long.
  final Duration retryDelay;

  /// How many tracks one search returns.
  static const limit = 20;

  @override
  OnlineSourceId get id => OnlineSourceId.jamendo;

  @override
  Future<List<OnlineItem>> search(String words) async {
    final found = await _search(words);
    if (found.isNotEmpty) return found;
    await Future<void>.delayed(retryDelay);
    return _search(words);
  }

  Future<List<OnlineItem>> _search(String words) async {
    final url = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
      'client_id': clientId,
      'format': 'json',
      'limit': '$limit',
      'search': words.trim(),
      'audioformat': 'mp32',
      'imagesize': '300',
    });
    final json = await fetchJson(fetch, url);
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
          ?_track(entry),
    ];
  }

  /// Reads one entry of Jamendo's track list. Returns null for an entry
  /// with nothing to play.
  static OnlineTrack? _track(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}';
    final title = json['name'];
    final stream = httpsUrl(json['audio']);
    if (id.isEmpty || title is! String || stream == null) return null;
    return OnlineTrack(
      id: id,
      title: title,
      streamUrl: stream,
      artist: text(json['artist_name']),
      album: text(json['album_name']),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      imageUrl: httpsUrl(json['album_image']) ?? httpsUrl(json['image']),
      downloadUrl: json['audiodownload_allowed'] == true
          ? httpsUrl(json['audiodownload'])
          : null,
      licenceUrl: text(json['license_ccurl']),
    );
  }
}
