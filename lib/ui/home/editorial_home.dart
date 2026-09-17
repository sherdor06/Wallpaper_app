import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../models/wallpaper.dart';
import '../../services/image_cache.dart';
import '../../services/remote_config_service.dart';
import '../widgets/wallpaper_grid.dart';
import 'category_carousel.dart';
import 'collection_accent.dart';
import 'collection_page.dart';

/// A themed row on the editorial home: a title and the category it draws from.
///
/// Kept as data rather than widgets so the line-up can move to Remote Config
/// without touching layout — and so a new category is one entry here, not a
/// new screen. A row whose category has no wallpapers yet is skipped, so an
/// entry can go in ahead of its content.
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
  /// The two accented collections lead (see [CollectionAccent]) — they are
  /// what the home screen exists to surface.
  static const _sections = [
    HomeSection('Girly', 'girly'),
    HomeSection('Aesthetic', 'aesthetic'),
    HomeSection('Popular', 'popular'),
    HomeSection('Nature', 'nature'),
    HomeSection('Space', 'space'),
  ];

  /// Fewest wallpapers the spotlighted category needs before it is
  /// announced — same bar as a collection card. Announcing a collection that
  /// opens onto five wallpapers would be worse than saying nothing.
  static const _minSpotlight = 12;

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

  /// The carousel's line-up: Remote Config's order, minus anything the
  /// catalog cannot back with a card's worth of wallpapers.
  List<CarouselCollection> _carousel() {
    final meta = {for (final c in catalog.categories) c.id: c};
    final out = <CarouselCollection>[];
    for (final id in RemoteConfigService.instance.homeStrip) {
      final items = catalog.wallpapers.where((w) => w.category == id).toList();
      if (items.length < _minSpotlight) continue;
      out.add(
        CarouselCollection(
          id: id,
          name: meta[id]?.name ?? categoryLabel(id),
          tagline: meta[id]?.tagline,
          items: items,
        ),
      );
    }
    return out;
  }

  /// The collection Remote Config says to announce, if it exists and has
  /// enough in it. Read at build so a config change shows on the next open
  /// without a restart being needed anywhere.
  _Featured? _featured() {
    final id = RemoteConfigService.instance.featuredCategory;
    if (id.isEmpty) return null;
    final items = catalog.wallpapers.where((w) => w.category == id).toList();
    final cover = Wallpaper.coverOf(items);
    if (items.length < _minSpotlight || cover == null) return null;
    final meta = catalog.categories.where((c) => c.id == id).firstOrNull;
    return _Featured(
      id: id,
      name: meta?.name ?? categoryLabel(id),
      tagline: meta?.tagline,
      items: items,
      cover: cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hero = _heroFor(DateTime.now());
    final featured = _featured();
    final carousel = _carousel();
    final bottom = MediaQuery.paddingOf(context).bottom + 8;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPadding)),
          if (hero != null) SliverToBoxAdapter(child: _Hero(wallpaper: hero)),
          if (carousel.length >= 2)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: CategoryCarousel(
                  collections: carousel,
                  onOpen: (c) => _open(context, c.id, c.name, c.items),
                ),
              ),
            ),
          if (featured != null)
            SliverToBoxAdapter(
              child: _Spotlight(
                featured: featured,
                onTap: () =>
                    _open(context, featured.id, featured.name, featured.items),
              ),
            ),
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

  void _open(
    BuildContext context,
    String id,
    String name,
    List<Wallpaper> items,
  ) {
    final tagline = catalog.categories
        .where((c) => c.id == id)
        .firstOrNull
        ?.tagline;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CollectionPage(id: id, name: name, tagline: tagline, items: items),
      ),
    );
  }

  List<Widget> _section(BuildContext context, HomeSection s) {
    final items = catalog.wallpapers
        .where((w) => w.category == s.category)
        .toList();
    if (items.isEmpty) return const [];
    // The header (title included), the "See all" pill and the trailing "+N"
    // card open the collection; the tiles open their wallpaper, as tiles do
    // everywhere else in the app.
    void open() => _open(context, s.category, s.title, items);
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          title: s.title,
          accent: CollectionAccent.custom(s.category),
          onSeeAll: open,
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _Row(
            items: items.take(_rowLength).toList(),
            accent: CollectionAccent.of(s.category),
            onTap: open,
          ),
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
    // "Sport 61" is a filename, not a headline. With the whole catalog coming
    // from feeds now, most days the rotation lands on an auto-titled one, so
    // lead with the category and let the line below say what the card is.
    final auto = wallpaper.isAutoTitled;
    final category = categoryLabel(wallpaper.category);
    final title = auto ? category : wallpaper.title;
    final subtitle = auto
        ? 'Wallpaper of the day · ${wallpaper.resolution}'
        : '$category · ${wallpaper.resolution}';
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
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C5CE7), Color(0xFF8E7BF5)],
                      ),
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
                        title,
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
                        subtitle,
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
}

/// What the spotlight announces, resolved once per build.
class _Featured {
  final String id;
  final String name;
  final List<Wallpaper> items;
  final Wallpaper cover;
  final String? tagline;
  const _Featured({
    required this.id,
    required this.name,
    required this.items,
    required this.cover,
    this.tagline,
  });
}

/// The "new collection" card under the hero. Wide and short so it reads as an
/// announcement, not a second hero; the cover shows through on the right and
/// the words sit on a scrim on the left.
class _Spotlight extends StatelessWidget {
  final _Featured featured;
  final VoidCallback onTap;
  const _Spotlight({required this.featured, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = CollectionAccent.of(featured.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: featured.cover.thumbUrl,
                  cacheManager: AppCache.thumbs,
                  fit: BoxFit.cover,
                  memCacheWidth: 800,
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      stops: [0, 0.55, 1],
                      colors: [
                        Color(0xE00E0E12),
                        Color(0x8C0E0E12),
                        Color(0x0D0E0E12),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  bottom: 16,
                  right: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: accent.gradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'NEW COLLECTION',
                          style: TextStyle(
                            color: accent.onColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            featured.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          if (featured.tagline != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              featured.tagline!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0x29FFFFFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x38FFFFFF)),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  /// A collection's own colour: a dot before the title and the "See all" in
  /// it. Null for rows in the app accent, which get no dot — the dot marks
  /// the exception, not the rule.
  final CollectionAccent? accent;

  const _SectionHeader({
    required this.title,
    required this.onSeeAll,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = accent?.color ?? scheme.primary;
    // The whole header is the tap target, not just the pill: the title is
    // what the eye lands on, so it should take the tap too.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSeeAll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent!.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
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
              Container(
                padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        color: tint,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: tint),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A horizontal run of small tiles, ending in a "See all" card. No badges
/// or heart here: the row is a taste of the category, and those affordances
/// belong to the grids where there is room for them.
///
/// A tile opens its wallpaper; the trailing card opens the collection.
class _Row extends StatelessWidget {
  final List<Wallpaper> items;
  final CollectionAccent accent;

  /// Opens the collection — the trailing card's tap.
  final VoidCallback onTap;

  const _Row({required this.items, required this.accent, required this.onTap});

  static const _width = 110.0;
  static const _height = 150.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        itemCount: items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == items.length) {
            return _MoreTile(accent: accent, onTap: onTap);
          }
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
                  placeholder: (_, __) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF1B1B22)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The last card in a row: a "See all" door in the collection's accent.
class _MoreTile extends StatelessWidget {
  final CollectionAccent accent;
  final VoidCallback onTap;

  const _MoreTile({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _Row._width,
        decoration: BoxDecoration(
          color: accent.color.withValues(alpha: dark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: accent.gradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: accent.onColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'See all',
              style: TextStyle(
                color: accent.color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
