import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// The searches the user has made lately, newest first, kept on the device.
class SearchHistory extends Notifier<List<String>> {
  static const _key = 'search_history';

  /// How many searches are remembered.
  static const limit = 10;

  @override
  List<String> build() =>
      ref.watch(sharedPreferencesProvider).getStringList(_key) ?? const [];

  /// Puts [query] at the top. One made before moves up rather than being
  /// listed twice, whatever its capitals.
  void add(String query) {
    final search = query.trim();
    if (search.isEmpty) return;
    _save(
      [
        search,
        for (final earlier in state)
          if (earlier.toLowerCase() != search.toLowerCase()) earlier,
      ].take(limit).toList(),
    );
  }

  void clear() => _save(const []);

  void _save(List<String> searches) {
    ref.read(sharedPreferencesProvider).setStringList(_key, searches);
    state = searches;
  }
}

final searchHistoryProvider = NotifierProvider<SearchHistory, List<String>>(
  SearchHistory.new,
);
