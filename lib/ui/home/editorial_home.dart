import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../models/wallpaper.dart';
import '../../services/image_cache.dart';
import '../widgets/wallpaper_grid.dart';
import 'category_page.dart';

/// A themed row on the editorial home: a title and the category it draws from.
///
/// Kept as data rather than widgets so the line-up can move to Remote Config
/// without touching layout — and so a new category ("aesthetic", once its
/// content lands) is one entry here, not a new screen.
class HomeSection {
  final String title;
  final String category;
  const HomeSection(this.title, this.category);
}

/// The curated home: a wallpaper of the day, a few themed rows, then the whole
/// catalog in the familiar grid.
///
/// Everything scrolls as one — the rows and hero are slivers above
/// [SliverWallpaperGrid], not a list wrapped around a grid, so there is a
/// single scroll position and pull-to-refresh works from the top.
class EditorialHome extends StatelessWidget {
  final Catalog catalog;
  final Future<void> Function() onRefresh;

  /// Clears the floating title row; the shell passes it in.
  final double topPadding;

  const EditorialHome({
    super.key,
    required this.catalog,
    required this.onRefresh,
    required this.topPadding,
  });

  /// Rows shown, in order. Empty categories are skipped at build time.
  static const _sections = [
    HomeSection('Popular', 'popular'),
    HomeSection('Nature', 'nature'),
    HomeSection('Space', 'space'),
  ];

  /// How many tiles a row carries. Enough to scroll into, few enough that the
  /// row still reads as a taste of the category rather than the category.
  static const _rowLength = 12;

  /// Today's hero, chosen by the date so it changes daily and is the same for
  /// everyone that day — a rotation, not a random reshuffle on every open.
  /// Live wallpapers are excluded: a still frame of a video reads as a broken
  /// image up here.
  Wallpaper? _heroFor(DateTime now) {
    final stills = catalog.wallpapers.where((w) => !w.isLive).toList();
    if (stills.isEmpty) return null;
    // Rotate through the titled ones: "Milky Way" carries a hero, "Space 12"
    // does not — and the untitled ones are the likelier mis-files (see
    // [Wallpaper.isAutoTitled]). Fall back to everything if none qualify.
    final titled = stills.where((w) => !w.isAutoTitled).toList();
    final pool = titled.isEmpty ? stills : titled;
    final day = now.difference(DateTime(2026)).inDays;
    return pool[day % pool.length];
  }

  @override
  Widget build(BuildContext context) {
    final hero = _heroFor(DateTime.now());
    final bottom = MediaQuery.paddingOf(context).bottom + 8;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          if (hero != null)
            SliverToBoxAdapter(child: _Hero(wallpaper: hero)),
          for (final s in _sections) ..._section(context, s),
          SliverToBoxAdapter(
            child: _SectionHeader(title: 'Browse all', onSeeAll: null),
          ),
          SliverWallpaperGrid(items: catalog.wallpapers),
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }

  List<Widget> _section(BuildContext context, HomeSection s) {
    final items =
        catalog.wallpapers.where((w) => w.category == s.category).toList();
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: s.title,
          onSeeAll: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CategoryPage(title: s.title, items: items),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _Row(items: items.take(_rowLength).toList()),
        ),
      ),
    ];
  }
}

/// Wallpaper of the day. Uses the thumbnail, not the full file: at this size
/// on a phone the 400px thumb is already sharper than the screen needs, and
/// the full 4K download would be several megabytes on every cold open.
class _Hero extends StatelessWidget {
  final Wallpaper wallpaper;
  const _Hero({required this.wallpaper});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: () => openWallpaper(context, wallpaper),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: wallpaper.thumbUrl,
                  cacheManager: AppCache.thumbs,
                  fit: BoxFit.cover,
                  memCacheWidth: 800,
                  placeholder: (_, __) => const ColoredBox(color: Color(0xFF1B1B22)),
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1B1B22)),
                ),
                // Scrim so the title reads on any image; matches the dark
                // scaffold so it looks like the card dissolves into the page.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.45, 1],
                      colors: [Color(0x000E0E12), Color(0xD90E0E12)],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6C5CE7), Color(0xFF8E7BF5)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'TODAY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        wallpaper.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_capitalize(wallpaper.category)} · ${wallpaper.resolution}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSeeAll,
              child: Padding(
                // Grows the tap target without moving the text.
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'See all',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontal run of small tiles. No badges or heart here: the row is a
/// taste of the category, and those affordances belong to the browse grid
/// where there is room for them.
class _Row extends StatelessWidget {
  final List<Wallpaper> items;
  const _Row({required this.items});

  static const _width = 110.0;
  static const _height = 150.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final w = items[i];
          return GestureDetector(
            onTap: () => openWallpaper(context, w),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: _width,
                child: CachedNetworkImage(
                  imageUrl: w.thumbUrl,
                  cacheManager: AppCache.thumbs,
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  placeholder: (_, __) => const ColoredBox(color: Color(0xFF1B1B22)),
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1B1B22)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
