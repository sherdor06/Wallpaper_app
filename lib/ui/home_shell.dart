import 'dart:io';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../services/favorites_service.dart';
import 'archive_page.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'settings_page.dart';
import 'widgets/ad_banner_placeholder.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/glass_nav_bar.dart';

const _accent = Color(0xFF6C5CE7);

/// Fraction of the native iOS tab bar's measured height that stays in the
/// layout. UIKit reports a height that includes home-indicator room at the
/// bottom; that room only reads correctly when the bar is the bottom-most view,
/// and here the ad banner is, so it becomes dead space that holds the bar up off
/// the banner. Dropping the tail of it lets the bar sit lower.
///
/// This is the one number to turn if the bar still sits too high (lower it) or
/// starts clipping its labels (raise it, up to 1.0 for no trim at all).
const _iosNavKeep = 0.82;


/// Root shell. The bottom navigation is platform-specific:
///   - iOS 26+  → native Liquid Glass [CNTabBar].
///   - iOS < 26 → floating frosted [GlassNavBar].
///   - Android  → solid [CircleNavBar] (no blur, no jank).
///
/// The *contents* of that bar differ by platform too — see [_archiveIsTab].
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _homeReset = 0; // bumped when Home is selected → resets its category to "All"

  /// True while the embedded Archive tab is in multi-select. The whole bottom
  /// chrome yields to it: the page hangs its selection bar off its own Scaffold,
  /// and with [Scaffold.extendBody] the body runs behind ours, so leaving either
  /// the nav bar or the ad banner up would bury that bar. Photos does the same.
  bool _archiveSelecting = false;

  /// iOS carries Archive in the tab bar (Home/Favorites/Archive/Settings);
  /// Android keeps it on the top chrome and its bar holds three items. Every
  /// list below is built from this flag so the pages, the nav items and the
  /// chrome can never drift out of step.
  bool get _archiveIsTab => Platform.isIOS;

  /// Index of the Settings tab — last on both platforms.
  int get _settingsIndex => _archiveIsTab ? 3 : 2;

  /// Tabs 0 and 1 are full-bleed grids that scroll under the floating chrome.
  /// Archive and Settings bring their own [AppBar], so the chrome hides for
  /// them rather than overlapping their title bars.
  bool get _gridTab => _index < 2;

  static const _gridTitles = ['Wallpapers', 'Favorites'];

  void _select(int i) => setState(() {
        _index = i;
        if (i == 0) _homeReset++;
      });

  List<Widget> get _pages => [
        HomeTab(resetSignal: _homeReset),
        const FavoritesTab(),
        if (_archiveIsTab)
          ArchivePage(
            onSelectingChanged: (v) => setState(() => _archiveSelecting = v),
          ),
        const SettingsPage(),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        return Scaffold(
          // No app bar: the grid fills the whole screen and scrolls behind the
          // floating chrome (title pill + archive button + bottom nav).
          extendBodyBehindAppBar: true,
          extendBody: true,
          body: Stack(
            children: [
              IndexedStack(index: _index, children: _pages),
              if (_gridTab)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          TitlePill(text: _gridTitles[_index]),
                          const Spacer(),
                          // Android only: on iOS this lives in the tab bar, and
                          // Settings is a tab on both platforms.
                          if (!_archiveIsTab)
                            ChromeIconButton(
                              icon: Icons.inventory_2_outlined,
                              tooltip: 'Archive',
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const ArchivePage()),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Floating glass nav on top, ad pinned to the very bottom.
          bottomNavigationBar: _archiveSelecting
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBottomNav(),
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const SafeArea(
                          top: false, child: AdBannerPlaceholder()),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    // A bar with a different item count than [_pages] silently maps taps to the
    // wrong screen, so tie the two together here rather than trusting the lists
    // to be edited in step.
    assert(_pages.length == _settingsIndex + 1);

    // iOS 26+: native Liquid Glass tab bar. Not split — that layout existed to
    // hang Search off to the right as a round pill, and Search is gone.
    // Safe to hard-code four items: isIOS26OrAbove implies iOS, which is
    // exactly when Archive is a tab.
    if (isIOS26OrAbove) {
      assert(_archiveIsTab && _pages.length == 4);
      // No fixed height: the package skips its intrinsic-size measurement
      // whenever one is given (tab_bar.dart `_requestIntrinsicSize`), and the 85
      // this used to pass was sized for three items — two labelled plus the
      // icon-only Search pill. Four labelled items do not fit 85 once the bar's
      // own home-indicator reserve is taken out of it, so the titles ride up
      // over the glyphs. Letting the native view report its own height gives
      // each item the room UIKit thinks it needs.
      return ClipRect(
        // Keeps the top of the bar and drops its dead bottom reserve — see
        // [_iosNavKeep]. Clipping rather than translating matters: a translated
        // bar would keep its hit box over the banner and swallow ad taps.
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _iosNavKeep,
          child: CNTabBar(
            currentIndex: _index,
            onTap: _select,
            tint: _accent,
            items: const [
              CNTabBarItem(label: 'Home', icon: CNSymbol('house.fill')),
              CNTabBarItem(label: 'Favorites', icon: CNSymbol('heart.fill')),
              CNTabBarItem(label: 'Archive', icon: CNSymbol('archivebox.fill')),
              CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape.fill')),
            ],
          ),
        ),
      );
    }

    final items = <GlassNavItem>[
      const GlassNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      ),
      const GlassNavItem(
        icon: Icons.favorite_border,
        activeIcon: Icons.favorite,
        label: 'Favorites',
      ),
      if (_archiveIsTab)
        const GlassNavItem(
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2,
          label: 'Archive',
        ),
      const GlassNavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
      ),
    ];
    assert(items.length == _pages.length);

    // Android: icon-only solid nav with a sliding accent circle (no blur — no jank).
    if (Platform.isAndroid) {
      return CircleNavBar(currentIndex: _index, onTap: _select, items: items);
    }

    // iOS < 26: floating frosted-glass nav with a sliding accent pill.
    return GlassNavBar(currentIndex: _index, onTap: _select, items: items);
  }
}
