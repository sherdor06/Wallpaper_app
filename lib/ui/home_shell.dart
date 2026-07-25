import 'dart:io';

import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/material.dart';

import '../services/favorites_service.dart';
import 'archive_page.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'search_tab.dart';
import 'settings_page.dart';
import 'widgets/ad_banner_placeholder.dart';
import 'widgets/floating_chrome.dart';
import 'widgets/glass_nav_bar.dart';

const _accent = Color(0xFF6C5CE7);

/// True on iOS 26+ (where the native Liquid Glass tab bar is available).
/// [Platform.operatingSystemVersion] is a free-form string, so parse defensively.
bool get _isIOS26OrAbove {
  if (!Platform.isIOS) return false;
  try {
    final match = RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion);
    if (match == null) return false;
    return int.parse(match.group(1)!) >= 26;
  } catch (_) {
    return false;
  }
}

/// Root shell. The bottom navigation is platform-specific:
///   - iOS 26+  → native Liquid Glass [CNTabBar] (Home/Favorites left, Search split right).
///   - Android / iOS < 26 → standard Material [NavigationBar].
/// All other surfaces stay liquid-glass (via liquid_glass_widgets).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _homeReset = 0; // bumped when Home is selected → resets its category to "All"

  static const _titles = ['Wallpapers', 'Favorites', 'Search'];

  void _select(int i) => setState(() {
        _index = i;
        if (i == 0) _homeReset++;
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        return Scaffold(
          // No app bar: the grid fills the whole screen and scrolls behind the
          // floating chrome (title pill + settings button + bottom nav).
          extendBodyBehindAppBar: true,
          extendBody: true,
          body: Stack(
            children: [
              IndexedStack(
                index: _index,
                children: [
                  HomeTab(resetSignal: _homeReset),
                  const FavoritesTab(),
                  const SearchTab(),
                ],
              ),
              // Floating top chrome: title pill (left) + settings (right),
              // each its own liquid/solid button — content shows through.
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
                        TitlePill(text: _titles[_index]),
                        const Spacer(),
                        ChromeIconButton(
                          icon: Icons.inventory_2_outlined,
                          tooltip: 'Archive',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ArchivePage()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ChromeIconButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Settings',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const SettingsPage()),
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
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBottomNav(),
              Container(
                width: double.infinity,
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const SafeArea(top: false, child: AdBannerPlaceholder()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    // iOS 26+: native Liquid Glass tab bar (Search split to the right, like the screenshot).
    if (_isIOS26OrAbove) {
      return CNTabBar(
        currentIndex: _index,
        onTap: _select,
        tint: _accent,
        height: 85,
        split: true,
        rightCount: 1,
        items: const [
          CNTabBarItem(label: 'Home', icon: CNSymbol('house.fill')),
          CNTabBarItem(label: 'Favorites', icon: CNSymbol('heart.fill')),
          CNTabBarItem(label: 'Search', icon: CNSymbol('magnifyingglass')),
        ],
      );
    }

    const items = [
      GlassNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        label: 'Home',
      ),
      GlassNavItem(
        icon: Icons.favorite_border,
        activeIcon: Icons.favorite,
        label: 'Favorites',
      ),
      GlassNavItem(
        icon: Icons.search,
        activeIcon: Icons.search,
        label: 'Search',
      ),
    ];

    // Android: icon-only solid nav with a sliding accent circle (no blur — no jank).
    if (Platform.isAndroid) {
      return CircleNavBar(currentIndex: _index, onTap: _select, items: items);
    }

    // iOS < 26: floating frosted-glass nav with a sliding accent pill.
    return GlassNavBar(currentIndex: _index, onTap: _select, items: items);
  }
}
