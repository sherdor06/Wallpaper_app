import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lottie/lottie.dart';

import '../../models/wallpaper.dart';
import '../detail_page.dart';
import 'wallpaper_tile.dart';

/// Number of columns for a grid [width] wide, chosen so each tile lands near
/// [target] logical pixels across.
///
/// The layout was drawn for a phone — two columns of roughly 190px. Hard-coding
/// that count makes a 10" tablet show two enormous tiles instead of more of the
/// catalog, so the count is derived from the width and the *tile* size is what
/// stays constant. Clamped at both ends: one column reads as broken, and past
/// six a thumbnail is too small to judge a wallpaper by.
int gridColumnsFor(
  double width, {
  double target = 190,
  int min = 2,
  int max = 6,
}) =>
    (width / target).round().clamp(min, max);

/// Reusable wallpaper grid shared by the Home and Favorites screens.
///
/// Takes an already-filtered list and opens the detail page on tap.
/// Provide [onRefresh] to enable pull-to-refresh.
class WallpaperGrid extends StatelessWidget {
  final List<Wallpaper> items;
  final Future<void> Function()? onRefresh;
  final String emptyText;

  /// Top inset so the first row starts below the translucent app bar (and any
  /// tab header) while still scrolling behind it.
  final double topPadding;

  const WallpaperGrid({
    super.key,
    required this.items,
    this.onRefresh,
    this.emptyText = 'No wallpapers',
    this.topPadding = 8,
  });

  void _open(BuildContext context, Wallpaper w) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailPage(wallpaper: w)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = items.isEmpty
        // Must be scrollable for RefreshIndicator to work.
        ? ListView(
            padding: EdgeInsets.only(top: topPadding),
            children: [
              const SizedBox(height: 80),
              Center(
                child: Lottie.asset(
                  'assets/anim/empty.json',
                  width: 160,
                  height: 160,
                  repeat: true,
                  // The empty state must never be the thing that breaks; a
                  // missing asset falls back to a plain icon.
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_not_supported_outlined,
                    size: 72,
                    color: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(emptyText, style: const TextStyle(color: Colors.white54))),
            ],
          )
        : LayoutBuilder(
            // Measures the grid itself rather than the window: this sits inside
            // the shell's padding, and on a tablet the difference is a whole
            // column.
            builder: (context, constraints) => MasonryGridView.count(
              // Top inset clears the translucent app bar; extra bottom padding
              // so the last row clears the floating nav + ad (extendBody adds
              // the bottom bar height to MediaQuery padding).
              padding: EdgeInsets.fromLTRB(
                  8, topPadding, 8, 8 + MediaQuery.of(context).padding.bottom),
              crossAxisCount: gridColumnsFor(constraints.maxWidth),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final w = items[index];
                return WallpaperTile(
                  wallpaper: w,
                  onTap: () => _open(context, w),
                );
              },
            ),
          );

    if (onRefresh == null) return child;
    return RefreshIndicator(onRefresh: onRefresh!, child: child);
  }
}
