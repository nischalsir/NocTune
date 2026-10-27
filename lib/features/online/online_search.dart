import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import 'archive_source.dart';
import 'audius_source.dart';
import 'jamendo_source.dart';
import 'musicbrainz_source.dart';
import 'online_source.dart';

/// What one source found for a search, and whether it is fresh.
@immutable
class OnlineResults {
  const OnlineResults(this.items, {this.failure, this.fromCache = false});

  final List<OnlineItem> items;

  /// The songs among [items].
  List<OnlineTrack> get tracks => items.whereType<OnlineTrack>().toList();

  /// Why these are not fresh results; null when they are.
  final OnlineFailure? failure;

  /// The items were saved from an earlier search of the same words.
  final bool fromCache;
}

/// The last online searches of each source, kept on the device so the same
/// search can show something when there is no connection.
class OnlineSearchCache {
  OnlineSearchCache(this._prefs);

  static const _key = 'online_search_cache_v2';

  /// Where searches were kept when Jamendo was the only source.
  static const _oldKey = 'online_search_cache';

  /// How many searches are kept for each source.
  static const limit = 20;

  final SharedPreferences _prefs;

  List<OnlineItem>? get(OnlineSourceId source, String words) {
    final saved = _read()[_entry(source, words)];
    if (saved is! List) return null;
    return [
      for (final entry in saved.whereType<Map<String, Object?>>())
        OnlineItem.fromJson(entry),
    ];
  }

  Future<void> put(
    OnlineSourceId source,
    String words,
    List<OnlineItem> items,
  ) async {
    final key = _entry(source, words);
    final entries = _read()..remove(key);
    // Newest last; this source's oldest drop off the front.
    final mine = [
      for (final entry in entries.keys)
        if (entry.startsWith('${source.name}:')) entry,
    ];
    for (final entry in mine.take(max(0, mine.length - limit + 1))) {
      entries.remove(entry);
    }
    entries[key] = [for (final item in items) item.toJson()];
    await _prefs.setString(_key, jsonEncode(entries));
  }

  Map<String, Object?> _read() {
    if (_prefs.containsKey(_oldKey)) _prefs.remove(_oldKey);
    final text = _prefs.getString(_key);
    if (text == null) return {};
    try {
      final json = jsonDecode(text);
      return json is Map<String, Object?> ? json : {};
    } on FormatException {
      return {};
    }
  }

  static String _entry(OnlineSourceId source, String words) =>
      '${source.name}:${words.trim().toLowerCase()}';
}

/// Jamendo, or null in a build without a client id.
final jamendoSourceProvider = Provider<JamendoSource?>(
  (ref) => kJamendoClientId.isEmpty
      ? null
      : JamendoSource(clientId: kJamendoClientId),
);

final audiusSourceProvider = Provider<AudiusSource>((ref) => AudiusSource());

final archiveSourceProvider = Provider<ArchiveSource>((ref) => ArchiveSource());

/// Whether search also asks online sources at all. On by default; the
/// switch is in Settings.
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

/// Whether search asks one source, when online search is on. On by default;
/// the switches are in Settings.
class OnlineSourceEnabled extends Notifier<bool> {
  OnlineSourceEnabled(this.source);

  final OnlineSourceId source;

  String get _key => 'online_source_${source.name}';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  void set(bool enabled) {
    ref.read(sharedPreferencesProvider).setBool(_key, enabled);
    state = enabled;
  }
}

final onlineSourceEnabledProvider =
    NotifierProvider.family<OnlineSourceEnabled, bool, OnlineSourceId>(
      OnlineSourceEnabled.new,
    );

/// The sources a search asks, in the order their results are mixed.
final onlineSourcesProvider = Provider<List<OnlineSource>>((ref) {
  if (!ref.watch(onlineSearchEnabledProvider)) return const [];
  return [
    for (final source in <OnlineSource?>[
      ref.watch(jamendoSourceProvider),
      ref.watch(audiusSourceProvider),
      ref.watch(archiveSourceProvider),
    ])
      if (source != null && ref.watch(onlineSourceEnabledProvider(source.id)))
        source,
  ];
});

/// How long typing has to pause before the sources are asked, so a search
/// is not sent for every letter.
final onlineSearchDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 450),
);

/// One source's results for a search. Null when there is nothing to ask: no
/// words, or the source is not being asked. Never fails: without a fresh
/// answer it falls back to the results saved from the last time the same
/// words were searched there, and says why.
final onlineSourceSearchProvider = FutureProvider.autoDispose
    .family<OnlineResults?, (OnlineSourceId, String)>((ref, request) async {
      final (id, query) = request;
      final words = query.trim();
      final source = ref
          .watch(onlineSourcesProvider)
          .where((source) => source.id == id)
          .firstOrNull;
      if (words.isEmpty || source == null) return null;
      await Future<void>.delayed(ref.read(onlineSearchDelayProvider));
      if (!ref.mounted) return null;

      final cache = OnlineSearchCache(ref.read(sharedPreferencesProvider));
      try {
        final items = await source.search(words);
        await cache.put(id, words, items);
        return OnlineResults(items);
      } on OnlineSearchException catch (error) {
        final saved = cache.get(id, words);
        return OnlineResults(
          saved ?? const [],
          failure: error.failure,
          fromCache: saved != null,
        );
      }
    });

final musicBrainzSourceProvider = Provider<MusicBrainzSource>(
  (ref) => MusicBrainzSource(),
);

/// The artist a search names and their newest releases, from MusicBrainz.
/// Null when online search is off, the words don't clearly name an artist,
/// or MusicBrainz can't be reached: the section is then left out.
final latestReleasesProvider = FutureProvider.autoDispose
    .family<(String, List<Release>)?, String>((ref, query) async {
      final words = query.trim();
      if (words.isEmpty || !ref.watch(onlineSearchEnabledProvider)) {
        return null;
      }
      await Future<void>.delayed(ref.read(onlineSearchDelayProvider));
      if (!ref.mounted) return null;
      try {
        return await ref.read(musicBrainzSourceProvider).latest(words);
      } on OnlineSearchException {
        return null;
      }
    });

/// The first of each list, then the second of each, and so on, so every
/// source's best matches are near the top.
List<OnlineItem> interleave(List<List<OnlineItem>> lists) => [
  for (var index = 0; lists.any((list) => index < list.length); index++)
    for (final list in lists)
      if (index < list.length) list[index],
];
