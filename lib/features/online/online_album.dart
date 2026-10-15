import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'online_search.dart';
import 'online_source.dart';

/// The track lists of the albums and shows opened lately, so one opened
/// before can be shown without a connection.
class OnlineAlbumCache {
  OnlineAlbumCache(this._prefs);

  static const _key = 'online_album_cache';

  /// How many albums are kept.
  static const limit = 20;

  final SharedPreferences _prefs;

  List<OnlineTrack>? get(OnlineAlbum album) {
    final saved = _read()[album.key];
    if (saved is! List) return null;
    return [
      for (final entry in saved.whereType<Map<String, Object?>>())
        OnlineTrack.fromJson(entry),
    ];
  }

  Future<void> put(OnlineAlbum album, List<OnlineTrack> tracks) async {
    final entries = _read()..remove(album.key);
    // Newest last; the oldest drop off the front.
    for (final key
        in entries.keys.take(max(0, entries.length - limit + 1)).toList()) {
      entries.remove(key);
    }
    entries[album.key] = [for (final track in tracks) track.toJson()];
    await _prefs.setString(_key, jsonEncode(entries));
  }

  Map<String, Object?> _read() {
    final text = _prefs.getString(_key);
    if (text == null) return {};
    try {
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? json : {};
    } on FormatException {
      return {};
    }
  }
}

/// The tracks of an Internet Archive album or show. Never fails: without a
/// fresh answer it shows the list saved the last time it was opened, if
/// any, and says why.
final onlineAlbumProvider = FutureProvider.autoDispose
    .family<OnlineResults, OnlineAlbum>((ref, album) async {
      final cache = OnlineAlbumCache(ref.read(sharedPreferencesProvider));
      try {
        final tracks = await ref.read(archiveSourceProvider).tracks(album);
        await cache.put(album, tracks);
        return OnlineResults(tracks);
      } on OnlineSearchException catch (error) {
        final saved = cache.get(album);
        return OnlineResults(
          saved ?? const [],
          failure: error.failure,
          fromCache: saved != null,
        );
      }
    });
