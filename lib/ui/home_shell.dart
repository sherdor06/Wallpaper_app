import 'dart:io';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../services/home_layout_service.dart';
import 'accent.dart';
import 'archive_page.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'search/search_page.dart';
import 'settings_page.dart';
import 'widgets/ad_banner_placeholder.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/glass_nav_bar.dart';


/// Fraction of the native iOS tab bar's measured height that stays in the
/// layout. UIKit reports a height that includes home-indicator room at the
/// bottom, and that room only reads correctly when the bar is the bottom-most
/// view — which it now is, since the ad banner moved above it. So nothing is
/// trimmed any more.
///
/// It was 0.82 while the banner sat underneath: the bar's reserve was dead
/// space then, holding it up off the ad. Restore a value below 1.0 only if the
/// banner ever goes back below the bar.
///
/// This is the one number to turn if the bar sits too low (lower it) or starts
/// clipping its labels (raise it, 1.0 for no trim at all).
const _iosNavKeep = 1.0;

/// Root shell. The bottom navigation is platform-specific:
///   - iOS 26+  → native Liquid Glass [CNTabBar].
///   - iOS < 26 → floating frosted [GlassNavBar].
///   - Android  → solid [CircleNavBar] (no blur, no jank).
///
/// The bar holds Home, Favorites and Settings everywhere; Archive is a button
/// in the top chrome. Search is a tab only where the bar can carry it as its
/// own pill — see [_searchIsTab].
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Search lives where the platform puts it. On iOS 26+ it is a tab, split
  /// off the bar as its own glass pill on the right — Apple's arrangement.
  /// Everywhere else — Android, iOS before 26 — a button in the top chrome
  /// pushes [SearchPage].
  ///
  /// A plain split-off tab rather than the package's `searchItem`: on iOS 27
  /// that native search role showed no field and never reported activation,
  /// so the page carries its own field and the bar just selects it.
  bool get _searchIsTab => isIOS26OrAbove;

  /// Index of the Settings tab; Search, where it is a tab, comes after.
  static const _settingsIndex = 2;

  /// Tabs 0 and 1 are full-bleed grids that scroll under the floating chrome.
  /// Archive and Settings bring their own [AppBar], so the chrome hides for
  /// them rather than overlapping their title bars.
  bool get _gridTab => _index < 2;

  static const _gridTitles = ['Wallpapers', 'Favorites'];

  void _select(int i) => setState(() => _index = i);

  List<Widget> get _pages => [
    const HomeTab(),
    // Its empty state offers a way to the catalog, which on both platforms
    // means switching tab — Favorites is a page in the stack, not a route.
    FavoritesTab(onBrowse: () => _select(0)),
    const SettingsPage(),
    if (_searchIsTab) const SearchPage(asTab: true),
  ];

  @override
  Widget build(BuildContext context) {
    // No ListenableBuilder here on purpose. This used to rebuild the whole
    // shell — every page in the IndexedStack, the nav bar and the ad banner —
    // on every favourite toggle, while using nothing from FavoritesService but
    // a static heart icon in the nav. The two places that actually care listen
    // for themselves: FavoritesTab for its list, and the heart on each tile.
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
                      // Home only: curated vs browse. Lives here rather than
                      // in the tab so the whole top row is one widget's
                      // business; it writes the service the tab listens to.
                      if (_index == 0) ...[
                        ListenableBuilder(
                          listenable: HomeLayoutService.instance,
                          builder: (context, _) => SegmentedPill<HomeLayout>(
                            value: HomeLayoutService.instance.layout,
                            onChanged: HomeLayoutService.instance.setLayout,
                            items: const [
                              SegmentedPillItem(
                                value: HomeLayout.editorial,
                                icon: Icons.auto_awesome_outlined,
                                label: 'For you',
                              ),
                              SegmentedPillItem(
                                value: HomeLayout.collections,
                                icon: Icons.grid_view_rounded,
                                label: 'Collections',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (!_searchIsTab) ...[
                        ChromeIconButton(
                          icon: Icons.search_rounded,
                          tooltip: 'Search',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ChromeIconButton(
                        icon: Icons.inventory_2_outlined,
                        tooltip: 'Archive',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ArchivePage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      // Ad above the nav, not below it. The bar is what the user reaches
      // for constantly, so it keeps the screen edge; putting the ad there
      // instead parks a tap target the user does not want exactly where
      // their thumb already lives.
      //
      // The bottom inset moves with the position: whichever child sits
      // last has to clear the gesture bar, and that is now the nav.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const AdBannerPlaceholder(),
          ),
          // iOS's native bar reserves the home-indicator room itself
          // (see [_iosNavKeep]); wrapping it too would inset twice.
          if (Platform.isIOS)
            _buildBottomNav()
          else
            SafeArea(top: false, child: _buildBottomNav()),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    // A bar with a different item count than [_pages] silently maps taps to the
    // wrong screen, so tie the two together here rather than trusting the lists
    // to be edited in step.
    assert(_pages.length == _settingsIndex + 1 + (_searchIsTab ? 1 : 0));

    // iOS 26+: native Liquid Glass tab bar — three tabs on the left and
    // Search split off as its own pill on the right. Safe to hard-code:
    // isIOS26OrAbove implies iOS, which is exactly when Search is a tab.
    if (isIOS26OrAbove) {
      assert(_searchIsTab && _pages.length == 4);
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
            tint: kAccent,
            // The last item rides alone on the right: a round glass pill
            // for Search, the shape Apple gives it.
            split: true,
            rightCount: 1,
            items: const [
              CNTabBarItem(label: 'Home', icon: CNSymbol('house.fill')),
              CNTabBarItem(label: 'Favorites', icon: CNSymbol('heart.fill')),
              CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape.fill')),
              CNTabBarItem(label: 'Search', icon: CNSymbol('magnifyingglass')),
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
