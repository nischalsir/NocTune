import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/noc_palette.dart';
import '../../core/widgets/empty_state.dart';
import '../library/track_list_view.dart';

/// Searches the library by title, artist, album and file name as you type.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
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
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.noc;
    final results = ref.watch(searchResultsProvider(_query));

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              focusNode: _focus,
              onChanged: (value) => setState(() => _query = value),
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
            child: _query.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.search_rounded,
                    title: 'Search your library',
                    message:
                        'Find a track by its title, artist, album or '
                        'file name.',
                  )
                : TrackListView(
                    tracks: results,
                    empty: EmptyState(
                      icon: Icons.music_off_outlined,
                      title: 'No matches',
                      message:
                          'Nothing in your library matches '
                          '"${_query.trim()}".',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
