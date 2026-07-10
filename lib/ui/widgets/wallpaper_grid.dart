import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:lottie/lottie.dart';

import '../../models/wallpaper.dart';
import '../detail_page.dart';
import 'wallpaper_tile.dart';

/// Reusable wallpaper grid shared by the Home, Favorites and Search screens.
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
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(emptyText, style: const TextStyle(color: Colors.white54))),
            ],
          )
        : MasonryGridView.count(
            // Top inset clears the translucent app bar; extra bottom padding so
            // the last row clears the floating nav + ad (extendBody adds the
            // bottom bar height to MediaQuery padding).
            padding: EdgeInsets.fromLTRB(
                8, topPadding, 8, 8 + MediaQuery.of(context).padding.bottom),
            crossAxisCount: 2,
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
          );

    if (onRefresh == null) return child;
    return RefreshIndicator(onRefresh: onRefresh!, child: child);
  }
}
