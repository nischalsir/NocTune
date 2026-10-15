import 'online_source.dart';

/// Searches the Internet Archive for recordings that may be shared: those
/// under a Creative Commons licence or in the public domain, and Live Music
/// Archive shows with MP3s. Never the ones the Archive only streams.
class ArchiveSource implements OnlineSource {
  ArchiveSource({this.fetch = fetchOverHttps});

  final OnlineFetch fetch;

  /// How many albums and shows one search returns.
  static const limit = 20;

  /// The MP3 files an item may have, best first. The first kind it has is
  /// the one played.
  static const _formats = ['VBR MP3', '128Kbps MP3', '64Kbps MP3'];

  @override
  OnlineSourceId get id => OnlineSourceId.archive;

  @override
  Future<List<OnlineItem>> search(String words) async {
    final query =
        '(${words.trim()}) AND ((mediatype:audio AND '
        '(licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)) OR '
        '(collection:etree AND format:"VBR MP3")) AND NOT collection:stream_only';
    final json = await fetchJson(
      fetch,
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': query,
        'fl[]': ['identifier', 'title', 'creator', 'mediatype', 'licenseurl'],
        'rows': '$limit',
        'output': 'json',
      }),
    );
    final response = json is Map<String, Object?> ? json['response'] : null;
    final docs = response is Map ? response['docs'] : null;
    if (docs is! List) throw _unreadable;
    return [
      for (final doc in docs.whereType<Map<String, Object?>>()) ?_album(doc),
    ];
  }

  /// The tracks of [album], in order.
  Future<List<OnlineTrack>> tracks(OnlineAlbum album) async {
    final json = await fetchJson(
      fetch,
      Uri.https('archive.org', '/metadata/${album.id}'),
    );
    if (json is! Map<String, Object?>) throw _unreadable;
    final files = [
      for (final file in (json['files'] as List? ?? const []).whereType<Map>())
        if (text(file['name']) != null &&
            file['private'] != true &&
            file['private'] != 'true')
          file,
    ];
    final format = _formats.firstWhere(
      (format) => files.any((file) => file['format'] == format),
      orElse: () => '',
    );
    final chosen = [
      for (final file in files)
        if (file['format'] == format) file,
    ]..sort(_inOrder);
    return [
      for (final file in chosen) _track(album, file['name'] as String, file),
    ];
  }

  static const _unreadable = OnlineSearchException(
    OnlineFailure.unavailable,
    'An unreadable answer',
  );

  static OnlineAlbum? _album(Map<String, Object?> doc) {
    final id = text(doc['identifier']);
    final title = _first(doc['title']);
    if (id == null || title == null) return null;
    return OnlineAlbum(
      source: OnlineSourceId.archive,
      id: id,
      title: title,
      creator: _first(doc['creator']),
      kind: doc['mediatype'] == 'etree'
          ? OnlineAlbumKind.show
          : OnlineAlbumKind.album,
      imageUrl: _cover(id),
      licenceUrl: text(doc['licenseurl']),
    );
  }

  static OnlineTrack _track(OnlineAlbum album, String name, Map file) {
    final url = Uri(
      scheme: 'https',
      host: 'archive.org',
      pathSegments: ['download', album.id, ...name.split('/')],
    );
    final base = name.split('/').last;
    final dot = base.lastIndexOf('.');
    return OnlineTrack(
      source: OnlineSourceId.archive,
      id: '${album.id}/$name',
      title: text(file['title']) ?? (dot > 0 ? base.substring(0, dot) : base),
      streamUrl: url,
      downloadUrl: url,
      artist: album.creator,
      album: album.title,
      duration: _length(file['length']),
      imageUrl: _cover(album.id),
      licenceUrl: album.licenceUrl,
    );
  }

  /// By track number, where a file has one, then by name.
  static int _inOrder(Map a, Map b) {
    final (x, y) = (_number(a['track']), _number(b['track']));
    if (x != y) {
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    }
    return (a['name'] as String).compareTo(b['name'] as String);
  }

  /// The number at the start of `01` or `3/12`.
  static int? _number(Object? track) => track is String
      ? int.tryParse(RegExp(r'^\d+').stringMatch(track.trim()) ?? '')
      : null;

  /// A length in seconds (`5232.01`) or as `m:ss` or `h:mm:ss`.
  static Duration _length(Object? value) {
    if (value is! String) return Duration.zero;
    final seconds = num.tryParse(value);
    if (seconds != null) return Duration(seconds: seconds.toInt());
    var total = 0;
    for (final part in value.split(':')) {
      final number = int.tryParse(part);
      if (number == null) return Duration.zero;
      total = total * 60 + number;
    }
    return Duration(seconds: total);
  }

  /// [value], or the first of a list of them.
  static String? _first(Object? value) =>
      value is List ? value.map(text).nonNulls.firstOrNull : text(value);

  static Uri _cover(String id) => Uri.https('archive.org', '/services/img/$id');
}
