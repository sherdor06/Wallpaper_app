import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const _accent = Color(0xFF6C5CE7);
const _accentLight = Color(0xFF8E7BF5);

/// One destination in [GlassNavBar] / [SegmentNavBar].
class GlassNavItem {
  final IconData icon; // shown when not selected
  final IconData activeIcon; // shown when selected
  final String label;

  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// A floating, frosted-glass bottom navigation bar with a sliding accent pill
/// (used on iOS < 26). Wallpapers stay visible scrolling behind the glass.
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 64,
            color: const Color(0x14FFFFFF), // ~8% white translucent glass
            padding: const EdgeInsets.all(6),
            child: _NavStack(
              currentIndex: currentIndex,
              onTap: onTap,
              items: items,
              pillRadius: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// A floating, solid bottom navigation bar (Android): icon-only, with a filled
/// accent circle that slides behind the selected icon.
///
/// No [BackdropFilter] — cheap to render, no jank.
class CircleNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const CircleNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C26),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0x14FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Sliding accent circle behind the selected icon.
            AnimatedAlign(
              alignment: Alignment(
                items.length == 1
                    ? 0
                    : -1 + currentIndex * (2 / (items.length - 1)),
                0,
              ),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / items.length,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [_accent, _accentLight],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: -1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Icon-only items on top.
            Row(
              children: [
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: Center(
                        child: Icon(
                          i == currentIndex
                              ? items[i].activeIcon
                              : items[i].icon,
                          size: 24,
                          color: i == currentIndex
                              ? Colors.white
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared body: a sliding accent indicator behind a row of [_NavItem]s.
class _NavStack extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;
  final double pillRadius;

  const _NavStack({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.pillRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Sliding accent indicator (pill / segment fill).
        AnimatedAlign(
          alignment: Alignment(
            // Map index 0..n-1 to Alignment.x -1..1.
            items.length == 1
                ? 0
                : -1 + currentIndex * (2 / (items.length - 1)),
            0,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: FractionallySizedBox(
            widthFactor: 1 / items.length,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accent, _accentLight]),
                borderRadius: BorderRadius.circular(pillRadius),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Tappable items on top of the indicator.
        Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: _NavItem(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? item.activeIcon : item.icon,
            size: 24,
            color: selected ? Colors.white : Colors.white70,
          ),
          // Label expands/fades in only for the selected item.
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
