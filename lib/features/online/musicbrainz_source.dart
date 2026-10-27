import 'package:flutter/foundation.dart';

import 'online_source.dart';

/// An album, EP or single, as MusicBrainz lists it. MusicBrainz has no
/// audio; a release is opened in Spotify or YouTube Music to be heard.
@immutable
class Release {
  const Release({
    required this.id,
    required this.title,
    required this.artist,
    required this.type,
    required this.date,
  });

  /// The release group's MusicBrainz id.
  final String id;
  final String title;
  final String artist;

  /// Album, EP or Single.
  final String type;

  /// When it first came out: a year, a month or a day, as `2026-10-02`.
  final String date;

  /// The front cover from the Cover Art Archive, when it has one.
  Uri get coverUrl =>
      Uri.https('coverartarchive.org', '/release-group/$id/front-250');
}

/// Finds an artist's newest releases on MusicBrainz, the open music
/// database. No key is needed, but every request must name the app, and
/// it allows about one request a second.
class MusicBrainzSource {
  MusicBrainzSource({OnlineFetch? fetch, this.gap = const Duration(seconds: 1)})
    : fetch = fetch ?? _fetch;

  final OnlineFetch fetch;

  /// The pause between two requests.
  final Duration gap;

  static const userAgent =
      'NocTune/1.10.0 ( https://github.com/nischalsir/NocTune )';

  /// How many releases [latest] returns.
  static const limit = 10;

  /// How sure MusicBrainz has to be that the words name the artist.
  static const minScore = 90;

  /// Releases that aren't new music: reissues, live sets, remixes, demos.
  static const _skipped = {
    'Compilation',
    'Live',
    'Remix',
    'DJ-mix',
    'Demo',
    'Interview',
    'Spokenword',
    'Audiobook',
    'Audio drama',
  };

  static Future<OnlineResponse> _fetch(Uri url) =>
      fetchOverHttps(url, headers: {'User-Agent': userAgent});

  /// The artist [words] name and their newest releases, newest first; null
  /// when the words don't clearly name an artist. Throws
  /// [OnlineSearchException] when MusicBrainz can't be asked.
  Future<(String, List<Release>)?> latest(String words) async {
    final artists = await fetchJson(
      fetch,
      _url('artist', {'query': words.trim(), 'limit': '1'}),
    );
    final found = artists is Map<String, Object?> ? artists['artists'] : null;
    final artist = found is List && found.isNotEmpty ? found.first : null;
    if (artist is! Map<String, Object?>) return null;
    final id = text(artist['id']);
    final name = text(artist['name']);
    final score = artist['score'];
    if (id == null || name == null || score is! num || score < minScore) {
      return null;
    }

    // MusicBrainz can't sort, and a busy artist has hundreds of releases,
    // so ask for the last few years first and all of them only if that's
    // empty.
    final since = DateTime.now().year - 2;
    var releases = await _releases(
      'arid:$id AND firstreleasedate:[$since TO *]',
      name,
    );
    if (releases.isEmpty) releases = await _releases('arid:$id', name);
    releases.sort((a, b) => b.date.compareTo(a.date));
    return (name, releases.take(limit).toList());
  }

  Future<List<Release>> _releases(String query, String artist) async {
    await Future<void>.delayed(gap);
    final json = await fetchJson(
      fetch,
      _url('release-group', {'query': query, 'limit': '100'}),
    );
    final groups = json is Map<String, Object?> ? json['release-groups'] : null;
    if (groups is! List) {
      throw const OnlineSearchException(
        OnlineFailure.unavailable,
        'An unreadable answer',
      );
    }
    return [
      for (final group in groups.whereType<Map<String, Object?>>())
        ?_release(group, artist),
    ];
  }

  /// Reads one release, credited to [artist] when it names no one.
  static Release? _release(Map<String, Object?> json, String artist) {
    final id = text(json['id']);
    final title = text(json['title']);
    final type = text(json['primary-type']);
    final date = text(json['first-release-date']);
    final secondary = json['secondary-types'];
    if (id == null ||
        title == null ||
        date == null ||
        !const {'Album', 'EP', 'Single'}.contains(type) ||
        (secondary is List && secondary.any(_skipped.contains))) {
      return null;
    }
    final credit = json['artist-credit'];
    final credited = credit is List
        ? [
            for (final part in credit.whereType<Map<String, Object?>>())
              '${part['name'] ?? ''}${part['joinphrase'] ?? ''}',
          ].join()
        : '';
    return Release(
      id: id,
      title: title,
      artist: credited.trim().isEmpty ? artist : credited,
      type: type!,
      date: date,
    );
  }

  static Uri _url(String entity, Map<String, String> query) =>
      Uri.https('musicbrainz.org', '/ws/2/$entity', {...query, 'fmt': 'json'});
}
