import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/wallpaper_repository.dart';
import '../../models/wallpaper.dart';
import '../../services/image_cache.dart';
import '../widgets/wallpaper_grid.dart' show gridColumnsFor;
import 'collection_page.dart';

/// The browse home: one card per category, tap into the one you want.
///
/// Replaces the chip row's job with something that can be seen rather than
/// read. Categories are ordered by size, fullest first, and the thin ones are
/// left out altogether — a card promising a collection and delivering three
/// wallpapers is worse than no card.
class CollectionsHome extends StatelessWidget {
  final Catalog catalog;
  final Future<void> Function() onRefresh;
  final double topPadding;

  const CollectionsHome({
    super.key,
    required this.catalog,
    required this.onRefresh,
    required this.topPadding,
  });

  /// Fewest wallpapers a category needs to earn a card. Below this the
  /// category still exists — its wallpapers are in every "Browse all" grid —
  /// it just is not advertised as a destination.
  static const _minItems = 12;

  List<_Collection> _collections() {
    final byId = <String, List<Wallpaper>>{};
    for (final w in catalog.wallpapers) {
      (byId[w.category] ??= []).add(w);
    }
    final meta = {for (final c in catalog.categories) c.id: c};
    final out = [
      for (final e in byId.entries)
        if (e.value.length >= _minItems)
          _Collection(
            id: e.key,
            name: meta[e.key]?.name ?? categoryLabel(e.key),
            tagline: meta[e.key]?.tagline,
            items: e.value,
          ),
    ]..sort((a, b) => b.items.length.compareTo(a.items.length));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final collections = _collections();
    final bottom = MediaQuery.paddingOf(context).bottom + 8;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          padding: EdgeInsets.fromLTRB(8, topPadding, 8, bottom),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            // Same column rule as the wallpaper grid, so a tablet gets more
            // cards rather than two enormous ones.
            crossAxisCount: gridColumnsFor(constraints.maxWidth),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.9,
          ),
          itemCount: collections.length,
          itemBuilder: (context, i) => _CollectionCard(
            collection: collections[i],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CollectionPage(
                  id: collections[i].id,
                  name: collections[i].name,
                  tagline: collections[i].tagline,
                  items: collections[i].items,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Collection {
  final String id;
  final String name;
  final List<Wallpaper> items;
  final String? tagline;
  const _Collection({
    required this.id,
    required this.name,
    required this.items,
    this.tagline,
  });
}

/// Cover image, name, tagline. The cover is [Wallpaper.coverOf] the set — the
/// first *titled* wallpaper, since the auto-titled ones are the likeliest to
/// be filed in the wrong category and a Space card wearing a car is worse
/// than no card.
class _CollectionCard extends StatelessWidget {
  final _Collection collection;
  final VoidCallback onTap;
  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cover = Wallpaper.coverOf(collection.items)!;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: cover.thumbUrl,
              cacheManager: AppCache.thumbs,
              fit: BoxFit.cover,
              memCacheWidth: 360,
              placeholder: (_, __) =>
                  const ColoredBox(color: Color(0xFF1B1B22)),
              errorWidget: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF1B1B22)),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.4, 1],
                  colors: [Color(0x000E0E12), Color(0xE00E0E12)],
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
                    collection.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (collection.tagline != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      collection.tagline!,
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
            ),
          ],
        ),
      ),
    );
  }
}
