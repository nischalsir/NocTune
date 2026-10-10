import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/layout/window_class.dart';
import '../core/theme/noc_palette.dart';
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
import 'nav_icon_animations.dart';
import 'noc_bottom_bar.dart';
import 'providers.dart';

// Search is last: when the tabs fold away it is the button kept on the right.
const _destinations = [
  NocDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
    motion: NavIconMotion.bounce,
  ),
  NocDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Library',
    motion: NavIconMotion.slide,
  ),
  NocDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Settings',
    motion: NavIconMotion.spin,
  ),
  NocDestination(
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
    label: 'Search',
    motion: NavIconMotion.bounce,
  ),
];

const _homeIndex = 0;
const _libraryIndex = 1;
const _searchIndex = 3;

/// The app frame: top-level destinations plus the persistent player bar.
///
/// Phones and tablets get the floating bottom bar, which folds its tabs away
/// while a page is being scrolled. Only wide, desktop-like windows switch to
/// a navigation rail.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = _homeIndex;
  final _libraryNavigator = GlobalKey<NavigatorState>();
  final _chrome = ChromeController();
  DateTime? _lastBackPress;

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
    _chrome.dispose();
    super.dispose();
  }

  void _select(int index) {
    // Any tap on the bar brings the tabs back.
    _chrome.expand();
    if (index == _index) {
      // Choosing the current destination again returns it to its first page.
      if (index == _libraryIndex) {
        _libraryNavigator.currentState?.popUntil((route) => route.isFirst);
      }
      return;
    }
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
    if (!MediaQuery.disableAnimationsOf(context)) _pageFade.forward(from: 0);
  }

  /// System back: leave an opened album or playlist, then return to Home,
  /// then ask for a second press before leaving the app.
  Future<void> _handleBack() async {
    if (_index == _libraryIndex &&
        await (_libraryNavigator.currentState?.maybePop() ??
            Future.value(false))) {
      return;
    }
    if (_index != _homeIndex) {
      _select(_homeIndex);
      return;
    }
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    _showMessage('Press back again to exit', seconds: 2);
  }

  void _showMessage(String message, {int seconds = 4}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: seconds),
        ),
      );
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
    final scanning = ref.watch(scanControllerProvider) is ScanRunning;
    final useRail = WindowClass.of(context) == WindowClass.expanded;
    // Folding the tabs is for touch layouts with room to spare: not while
    // typing, and not when the text is so large the folded bar would crowd.
    final canFoldTabs =
        !useRail &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        MediaQuery.textScalerOf(context).scale(15) <= 20;

    final destinations = [
      HomeScreen(
        onOpenSearch: () => _select(_searchIndex),
        onOpenLibrary: () => _select(_libraryIndex),
      ),
      // The library has its own navigator, so opening an album or playlist
      // keeps the navigation and mini-player on screen.
      Navigator(
        key: _libraryNavigator,
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
      ),
      const SettingsScreen(),
      const SearchScreen(),
    ];

    final pages = NotificationListener<ScrollNotification>(
      onNotification: (notification) =>
          canFoldTabs && _chrome.handleScroll(notification),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _pageFade, curve: Curves.easeOut),
        // IndexedStack keeps each destination's scroll position and state.
        child: IndexedStack(
          index: _index,
          children: [
            for (final (index, page) in destinations.indexed)
              // Animations on hidden destinations are paused.
              TickerMode(enabled: index == _index, child: page),
          ],
        ),
      ),
    );

    final Widget scaffold;
    if (useRail) {
      scaffold = Scaffold(
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
    } else {
      scaffold = Scaffold(
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
            minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              // On tablets the bar stays phone-sized and centred.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _chrome,
                  builder: (context, collapsed, _) => NocBottomBar(
                    collapsed: canFoldTabs && collapsed,
                    destinations: _destinations,
                    selectedIndex: _index,
                    onSelected: _select,
                    badgedIndex: scanning ? _libraryIndex : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Back is handled here rather than popping the app's only route.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: scaffold,
    );
  }
}
