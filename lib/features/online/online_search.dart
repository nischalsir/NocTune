import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'jamendo_source.dart';
import 'online_source.dart';

/// What an online search found, and whether it is fresh.
@immutable
class OnlineResults {
  const OnlineResults(this.tracks, {this.failure, this.fromCache = false});

  final List<OnlineTrack> tracks;

  /// Why these are not fresh results; null when they are.
  final OnlineFailure? failure;

  /// The tracks were saved from an earlier search of the same words.
  final bool fromCache;
}

/// The last online searches, kept on the device so the same search can show
/// something when there is no connection.
class OnlineSearchCache {
  OnlineSearchCache(this._prefs);

  static const _key = 'online_search_cache';

  /// How many searches are kept.
  static const limit = 20;

  final SharedPreferences _prefs;

  List<OnlineTrack>? get(String query) {
    final saved = _read()[_normal(query)];
    if (saved is! List) return null;
    return [
      for (final entry in saved.whereType<Map<String, Object?>>())
        OnlineTrack.fromJson(entry),
    ];
  }

  Future<void> put(String query, List<OnlineTrack> tracks) async {
    final key = _normal(query);
    final entries = _read()..remove(key);
    // Newest last; the oldest drop off the front.
    final kept = {
      for (final entry in entries.entries.skip(
        entries.length >= limit ? entries.length - limit + 1 : 0,
      ))
        entry.key: entry.value,
      key: [for (final track in tracks) track.toJson()],
    };
    await _prefs.setString(_key, jsonEncode(kept));
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

  static String _normal(String query) => query.trim().toLowerCase();
}

/// Jamendo, or null in a build without a client id.
final jamendoSourceProvider = Provider<JamendoSource?>(
  (ref) => kJamendoClientId.isEmpty
      ? null
      : JamendoSource(clientId: kJamendoClientId),
);

/// Whether search also asks Jamendo. On by default; the switch is in
/// Settings.
class OnlineSearchEnabled extends Notifier<bool> {
  static const _key = 'online_search_enabled';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  void set(bool enabled) {
    ref.read(sharedPreferencesProvider).setBool(_key, enabled);
    state = enabled;
  }
}

final onlineSearchEnabledProvider = NotifierProvider<OnlineSearchEnabled, bool>(
  OnlineSearchEnabled.new,
);

/// How long typing has to pause before Jamendo is asked, so a search is not
/// sent for every letter.
final onlineSearchDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 450),
);

/// Jamendo's tracks for a search. Null when there is nothing to ask: no
/// words, online search switched off, or a build without a client id.
/// Never fails: without a fresh answer it falls back to the results saved
/// from the last time the same words were searched, and says why.
final onlineSearchProvider = FutureProvider.autoDispose
    .family<OnlineResults?, String>((ref, query) async {
      final words = query.trim();
      final client = ref.watch(jamendoSourceProvider);
      if (words.isEmpty ||
          client == null ||
          !ref.watch(onlineSearchEnabledProvider)) {
        return null;
      }
      await Future<void>.delayed(ref.read(onlineSearchDelayProvider));
      if (!ref.mounted) return null;

      final cache = OnlineSearchCache(ref.read(sharedPreferencesProvider));
      try {
        final tracks = (await client.search(words)).cast<OnlineTrack>();
        await cache.put(words, tracks);
        return OnlineResults(tracks);
      } on OnlineSearchException catch (error) {
        final saved = cache.get(words);
        return OnlineResults(
          saved ?? const [],
          failure: error.failure,
          fromCache: saved != null,
        );
      }
    });
