import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../library/track_list_view.dart';
import 'search_history.dart';

/// Searches the library by title, artist, album and file name as you type.
/// With nothing typed it lists the searches made lately, to run again.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  final _focus = FocusNode();
  bool _wasShowing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The page stays alive while another tab is showing, with its tickers
    // paused. When it comes to the front, put the cursor in the field so the
    // keyboard opens straight away.
    final showing = TickerMode.valuesOf(context).enabled;
    if (showing && !_wasShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
    _wasShowing = showing;
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A search counts as made once it is sent from the keyboard or one of its
  /// results is played, not on every letter typed.
  void _remember() => ref.read(searchHistoryProvider.notifier).add(_query);

  void _searchAgain(String search) {
    _field.value = TextEditingValue(
      text: search,
      selection: TextSelection.collapsed(offset: search.length),
    );
    setState(() => _query = search);
    _remember();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final results = ref.watch(searchResultsProvider(_query));
    final history = ref.watch(searchHistoryProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _field,
              focusNode: _focus,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) => _remember(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tracks, artists, albums…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: palette.glass,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: palette.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide(color: palette.glassBorder),
                ),
              ),
            ),
          ),
          Expanded(
            child: _query.trim().isNotEmpty
                ? TrackListView(
                    tracks: results,
                    onPlayed: _remember,
                    empty: EmptyState(
                      icon: Icons.music_off_outlined,
                      title: 'No matches',
                      message:
                          'Nothing in your library matches '
                          '"${_query.trim()}".',
                    ),
                  )
                : history.isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search your library',
                    message:
                        'Find a track by its title, artist, album or '
                        'file name.',
                  )
                : _RecentSearches(
                    searches: history,
                    onSearch: _searchAgain,
                    onClear: ref.read(searchHistoryProvider.notifier).clear,
                  ),
          ),
        ],
      ),
    );
  }
}

/// The searches made lately, newest first, each a tap away from being run
/// again.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.searches,
    required this.onSearch,
    required this.onClear,
  });

  final List<String> searches;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Recent searches', style: text.titleMedium),
                ),
              ),
              TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
        for (final search in searches)
          ListTile(
            leading: Icon(Icons.history_rounded, color: palette.textTertiary),
            title: Text(
              search,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge,
            ),
            onTap: () => onSearch(search),
          ),
      ],
    );
  }
}
