import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/wallpaper.dart';
import '../detail_page.dart';
import 'empty_state.dart';
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

  /// Shown instead of [emptyText] when the list is empty — an [EmptyState] for
  /// screens that have something to say about *why* they are empty. Home has
  /// nothing to say (an empty catalog is a fault, not a state the user created),
  /// so it stays on the plain line.
  final Widget? empty;

  /// Top inset so the first row starts below the translucent app bar (and any
  /// tab header) while still scrolling behind it.
  final double topPadding;

  const WallpaperGrid({
    super.key,
    required this.items,
    this.onRefresh,
    this.emptyText = 'No wallpapers',
    this.empty,
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
        ? _buildEmpty(context)
        : LayoutBuilder(
            // Measures the grid itself rather than the window: this sits inside
            // the shell's padding, and on a tablet the difference is a whole
            // column.
            builder: (context, constraints) => MasonryGridView.count(
              // Top inset clears the translucent app bar; extra bottom padding
              // so the last row clears the floating nav + ad (extendBody adds
              // the bottom bar height to MediaQuery padding).
              padding: EdgeInsets.fromLTRB(
                  8, topPadding, 8, 8 + MediaQuery.paddingOf(context).bottom),
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

  /// The empty view, centred in whatever room is left between the floating top
  /// chrome and the bottom nav — and scrollable even though it always fits, or
  /// [RefreshIndicator] would have nothing to pull on.
  Widget _buildEmpty(BuildContext context) {
    // The shell uses extendBody, so the nav bar and the ad banner sit *over* the
    // bottom of this box; centring in the raw height would tuck the action
    // button under them.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: topPadding, bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // An unbounded parent would make this infinite and blow up the
            // layout, so fall back to hugging the content there.
            minHeight: constraints.hasBoundedHeight
                ? math.max(0, constraints.maxHeight - topPadding - bottomInset)
                : 0,
          ),
          child: Center(
            child: empty ??
                EmptyState(
                  animation: 'assets/anim/empty.json',
                  headline: emptyText,
                  fallbackIcon: Icons.image_not_supported_outlined,
                ),
          ),
        ),
      ),
    );
  }
}
