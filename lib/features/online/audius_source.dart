import 'online_source.dart';

/// Searches Audius, where artists put up their own music, through its open
/// API. No key is needed; requests carry NocTune's name.
class AudiusSource implements OnlineSource {
  AudiusSource({this.fetch = fetchOverHttps});

  final OnlineFetch fetch;

  static const appName = 'NocTune';

  /// How many tracks one search returns.
  static const limit = 20;

  @override
  OnlineSourceId get id => OnlineSourceId.audius;

  @override
  Future<List<OnlineItem>> search(String words) async {
    final json = await fetchJson(
      fetch,
      Uri.https('api.audius.co', '/v1/tracks/search', {
        'query': words.trim(),
        'app_name': appName,
        'limit': '$limit',
      }),
    );
    final data = json is Map<String, Object?> ? json['data'] : null;
    if (data is! List) {
      throw const OnlineSearchException(
        OnlineFailure.unavailable,
        'An unreadable answer',
      );
    }
    return [
      for (final entry in data.whereType<Map<String, Object?>>())
        ?_track(entry),
    ];
  }

  /// Reads one track. Returns null for one Audius won't stream to anyone,
  /// or only to fans who unlocked it.
  static OnlineTrack? _track(Map<String, Object?> json) {
    final id = text(json['id']);
    final title = text(json['title']);
    final access = json['access'];
    final streams =
        json['is_streamable'] == true &&
        json['is_stream_gated'] != true &&
        !(access is Map && access['stream'] == false);
    if (id == null || title == null || !streams) return null;

    final user = json['user'];
    final artwork = json['artwork'];
    final downloads =
        json['is_downloadable'] == true && json['is_download_gated'] != true;
    return OnlineTrack(
      source: OnlineSourceId.audius,
      id: id,
      title: title,
      streamUrl: _address(id, 'stream'),
      artist: user is Map ? text(user['name']) : null,
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      imageUrl: artwork is Map ? httpsUrl(artwork['480x480']) : null,
      downloadUrl: downloads ? _address(id, 'download') : null,
    );
  }

  /// A stable address for the track that redirects to the file; the signed
  /// links in a search answer are only good for a while.
  static Uri _address(String id, String what) =>
      Uri.https('api.audius.co', '/v1/tracks/$id/$what', {'app_name': appName});
}
