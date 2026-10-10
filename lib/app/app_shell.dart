import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/noc_palette.dart';
import '../core/widgets/noc_backdrop.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/scan/scan_controller.dart';
import '../features/playback/mini_player.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_screen.dart';
import '../features/startup/startup_prompts.dart';
import '../features/startup/update_dialog.dart';
import '../features/startup/welcome_dialog.dart';
import '../third_party/spotiflac/mornye_bottom_bar.dart';
import '../third_party/spotiflac/mornye_chrome.dart';
import '../third_party/spotiflac/mornye_theme.dart';
import '../third_party/spotiflac/runtime_profile_provider.dart';
import 'providers.dart';

const _homeIndex = 0;
const _libraryIndex = 1;
const _searchIndex = 2;

/// Window width from which a navigation rail replaces the bottom bar. As in
/// the navigation's source, tablets keep the bottom bar in both orientations;
/// the rail is for desktop-width windows.
const _navigationRailBreakpoint = 1440.0;

/// The app frame: Home, Library and Search behind the floating glass bar,
/// with the mini-player riding on top of it. Settings opens as a page from
/// the home screen rather than taking a slot in the bar.
///
/// The bar itself, its theme and its fold-on-scroll controller are the
/// navigation shell from `third_party/spotiflac`; this class wires them to
/// NocTune's screens the way that project's main shell does.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = _homeIndex;
  final _libraryNavigator = GlobalKey<NavigatorState>();
  final _mornyeChrome = MornyeChromeController();
  DateTime? _lastBackPress;
  bool _settingsPageOpen = false;

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
    _mornyeChrome.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    // Any tap on the bar brings the tabs back.
    _mornyeChrome.expand();
    if (_currentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _openSettings() async {
    if (_settingsPageOpen) return;
    _settingsPageOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    } finally {
      _settingsPageOpen = false;
    }
  }

  /// System back: leave an opened album or playlist, dismiss the keyboard on
  /// Search, return to Home, then ask for a second press before leaving.
  Future<void> _handleBackPress() async {
    if (_currentIndex == _libraryIndex &&
        await (_libraryNavigator.currentState?.maybePop() ??
            Future.value(false))) {
      _lastBackPress = null;
      return;
    }
    if (!mounted) return;
    if (_currentIndex == _searchIndex &&
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _lastBackPress = null;
      return;
    }
    if (_currentIndex != _homeIndex) {
      _onNavTap(_homeIndex);
      _lastBackPress = null;
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
    // The bar keeps its own theme: it is drawn exactly as in its source app,
    // whatever accent the rest of NocTune is using. NocTune's palette rides
    // along for the cover placeholder in the mini-player.
    final barBase = MornyeTheme.build(Theme.of(context).brightness);
    final barTheme = barBase.copyWith(
      extensions: [...barBase.extensions.values, palette],
    );
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(CupertinoIcons.house_fill),
        label: 'Home',
      ),
      const NavigationDestination(
        // The badge counts queued work in the navigation's source app.
        // NocTune has nothing to count, so it stays at zero.
        icon: MornyeNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        label: 'Library',
      ),
      const NavigationDestination(
        icon: Icon(CupertinoIcons.search),
        label: 'Search',
      ),
    ];

    final screenSize = MediaQuery.sizeOf(context);
    final useNavigationRail = screenSize.width >= _navigationRailBreakpoint;
    // Folding the tabs is for touch layouts with room to spare: not while
    // typing, and not when the text is so large the folded bar would crowd.
    final canMinimizeChrome =
        ref.watch(settingsProvider.select((s) => s.foldNavigationOnScroll)) &&
        !useNavigationRail &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        MediaQuery.textScalerOf(context).scale(15) <= 20;

    Widget observeScroll(Widget child, int index) =>
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (canMinimizeChrome && index == _currentIndex) {
              return _mornyeChrome.handleScroll(notification);
            }
            return false;
          },
          child: child,
        );

    final tabs = <Widget>[
      HomeScreen(
        onOpenSearch: () => _onNavTap(_searchIndex),
        onOpenLibrary: () => _onNavTap(_libraryIndex),
        onOpenSettings: _openSettings,
      ),
      // The library has its own navigator, so opening an album or playlist
      // keeps the navigation and mini-player on screen.
      Navigator(
        key: _libraryNavigator,
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => const LibraryScreen()),
      ),
      const SearchScreen(),
    ];

    // IndexedStack keeps each destination's scroll position and state; the
    // glass pill owns the tab transition, so the pages themselves just swap.
    final pageView = IndexedStack(
      index: _currentIndex,
      children: [
        for (final (index, tab) in tabs.indexed)
          // Animations on hidden destinations are paused.
          TickerMode(
            enabled: index == _currentIndex,
            child: observeScroll(tab, index),
          ),
      ],
    );

    final scaffold = Scaffold(
      // Content scrolls underneath the floating glass chrome.
      extendBody: true,
      body: NocBackdrop(
        child: useNavigationRail
            ? Row(
                children: [
                  SafeArea(
                    right: false,
                    bottom: false,
                    // On short windows the rail scrolls instead of
                    // overflowing.
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: NavigationRail(
                              selectedIndex: _currentIndex,
                              onDestinationSelected: _onNavTap,
                              labelType: NavigationRailLabelType.all,
                              backgroundColor: Colors.transparent,
                              destinations: [
                                for (final destination in destinations)
                                  NavigationRailDestination(
                                    icon: destination.icon,
                                    label: Text(destination.label),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: palette.glassBorder),
                  Expanded(child: pageView),
                ],
              )
            : pageView,
      ),
      bottomNavigationBar: Theme(
        data: barTheme,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: useNavigationRail
              ? const MiniPlayer()
              : ValueListenableBuilder<bool>(
                  valueListenable: _mornyeChrome,
                  builder: (context, collapsed, _) => MornyeBottomBar(
                    collapsed: canMinimizeChrome && collapsed,
                    destinations: destinations,
                    selectedIndex: _currentIndex,
                    onSelected: _onNavTap,
                    onHome: () => _onNavTap(_homeIndex),
                    onSearch: () => _onNavTap(_searchIndex),
                    blurEnabled: ref.watch(mornyeBlurEnabledProvider),
                  ),
                ),
        ),
      ),
    );

    // Back is handled here rather than popping the app's only route.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackPress();
      },
      child: scaffold,
    );
  }
}
