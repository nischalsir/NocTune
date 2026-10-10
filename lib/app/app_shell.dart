import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/window_class.dart';
import '../core/theme/noc_palette.dart';
import '../core/widgets/glass_panel.dart';
import '../core/widgets/noc_backdrop.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/scan/scan_controller.dart';
import '../features/playback/mini_player.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/startup/startup_prompts.dart';
import '../features/startup/update_dialog.dart';
import '../features/startup/welcome_dialog.dart';
import 'providers.dart';

typedef _Destination = ({IconData icon, IconData selectedIcon, String label});

const _destinations = <_Destination>[
  (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
  (
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Library',
  ),
  (
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
    label: 'Search',
  ),
  (
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];

const _libraryIndex = 1;
const _searchIndex = 2;

/// The app frame: top-level destinations plus the persistent mini-player.
/// Phones get a floating bottom bar; wider windows get a navigation rail.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  final _libraryNavigator = GlobalKey<NavigatorState>();

  // Fades a destination in when it is selected.
  late final _pageFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  late final _startupPrompts = StartupPrompts(
    welcome: WelcomeStore(ref.read(sharedPreferencesProvider)),
    checkForUpdate: () async =>
        (await ref.read(updateServiceProvider.future)).check(),
    showWelcome: () => showWelcomeDialog(context),
    showUpdate: (prompt) async =>
        mounted ? showUpdateDialog(context, prompt) : null,
    canInterrupt: () => mounted && (ModalRoute.of(context)?.isCurrent ?? false),
    onUpdateChoice: (prompt, choice) async => applyUpdateChoice(
      await ref.read(updateServiceProvider.future),
      prompt,
      choice,
    ),
  );

  @override
  void initState() {
    super.initState();
    // Everything here waits for the first frame, so the home screen is on
    // screen before any of it starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pick up files added or removed since the last launch.
      ref.read(scanControllerProvider.notifier).refreshIfPermitted();
      _startupPrompts.run();
    });
  }

  @override
  void dispose() {
    _pageFade.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    if (!MediaQuery.disableAnimationsOf(context)) _pageFade.forward(from: 0);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackErrorProvider, (_, next) {
      final message = next.value;
      if (message != null) _showMessage(message);
    });
    ref.listen(scanControllerProvider, (previous, next) {
      final summary = next is ScanIdle ? next.lastScan : null;
      if (previous is! ScanRunning || summary == null) return;
      if (summary.cancelled) {
        _showMessage('Scan cancelled. ${summary.scanned} tracks were read.');
      } else if (summary.scanned > 0 || summary.removed > 0) {
        _showMessage(
          'Library updated: ${summary.scanned} added or changed, '
          '${summary.removed} removed.',
        );
      } else if (summary.total == 0) {
        _showMessage('No music was found on this device.');
      }
    });

    final palette = context.noc;
    // IndexedStack keeps each destination's scroll position and state alive.
    final pages = FadeTransition(
      opacity: CurvedAnimation(parent: _pageFade, curve: Curves.easeOut),
      child: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            onOpenSearch: () => _select(_searchIndex),
            onOpenLibrary: () => _select(_libraryIndex),
          ),
          // The library has its own navigator, so opening an album or playlist
          // keeps the navigation and mini-player on screen.
          NavigatorPopHandler(
            enabled: _index == _libraryIndex,
            onPopWithResult: (_) => _libraryNavigator.currentState?.maybePop(),
            child: Navigator(
              key: _libraryNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const LibraryScreen(),
              ),
            ),
          ),
          const SearchScreen(),
          const SettingsScreen(),
        ],
      ),
    );

    if (WindowClass.of(context) == WindowClass.compact) {
      return Scaffold(
        // Content scrolls underneath the floating glass chrome.
        extendBody: true,
        body: NocBackdrop(child: pages),
        // Content dissolves into the page colour as it passes under the
        // floating bars, instead of showing sharply in the gaps around them.
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.backgroundDeep.withValues(alpha: 0),
                palette.backgroundDeep.withValues(alpha: 0.94),
              ],
              stops: const [0, 0.7],
            ),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                const SizedBox(height: 8),
                GlassPanel(
                  chrome: true,
                  padding: EdgeInsets.zero,
                  radius: 24,
                  child: NavigationBar(
                    height: 64,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    indicatorColor: palette.accent.withValues(alpha: 0.22),
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final destination in _destinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: NocBackdrop(
        child: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                backgroundColor: Colors.transparent,
                indicatorColor: palette.accent.withValues(alpha: 0.22),
                labelType: NavigationRailLabelType.all,
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final destination in _destinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: palette.glassBorder),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: pages),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    // Capped so the player doesn't stretch across a tablet.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: kMaxContentWidth,
                      ),
                      child: const MiniPlayer(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
